//! The master end of a terminal's pseudo-terminal, as the helper hands it
//! over: non-blocking reads and writes for the WebSocket relay, and resizes.

use std::io;
use std::os::fd::OwnedFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use rustix::fs::{OFlags, fcntl_getfl, fcntl_setfl};
use rustix::io::fcntl_dupfd_cloexec;
use rustix::termios::{Winsize, tcsetwinsize};
use tokio::io::unix::{AsyncFd, AsyncFdReadyGuard};

/// How long a new shell has to open its side of the pseudo-terminal.
const START_GRACE: Duration = Duration::from_secs(5);
/// How often that is looked at meanwhile.
const START_POLL: Duration = Duration::from_millis(50);

/// The descriptor, as the runtime watches it.
type Watch = Arc<AsyncFd<OwnedFd>>;

/// A pseudo-terminal's master end.
pub struct Pty {
    /// Replaced by [`Pty::renew`] when it has seen a hang-up.
    watch: Mutex<Watch>,
    /// Set once the shell has written something.
    started: AtomicBool,
}

impl Pty {
    /// Takes over `master` and makes it non-blocking.
    ///
    /// # Errors
    /// Fails when the descriptor cannot be watched (it is not a terminal or
    /// a socket, or there is no runtime).
    pub fn new(master: OwnedFd) -> io::Result<Self> {
        fcntl_setfl(&master, fcntl_getfl(&master)? | OFlags::NONBLOCK)?;
        Ok(Self { watch: Mutex::new(watched(master)?), started: AtomicBool::new(false) })
    }

    fn watch(&self) -> Watch {
        self.watch.lock().unwrap_or_else(PoisonError::into_inner).clone()
    }

    /// Watches the terminal afresh, through a copy of its descriptor, when
    /// `stale` is still the one in use.
    ///
    /// Linux hangs the master up for a moment while systemd sets the
    /// terminal up, before the shell opens it. The runtime never forgets a
    /// hang-up: from then on it calls the descriptor ready at once, every
    /// time, so a wait for the shell's next output would spin without ever
    /// pausing, and nothing else of the terminal (the browser leaving, for
    /// one) would be looked at again.
    fn renew(&self, stale: &Watch) -> io::Result<()> {
        let fresh = watched(fcntl_dupfd_cloexec(stale.get_ref(), 0)?)?;
        let mut watch = self.watch.lock().unwrap_or_else(PoisonError::into_inner);
        if Arc::ptr_eq(&watch, stale) {
            *watch = fresh;
        }
        Ok(())
    }

    /// After a read or write that had nothing to do: a wait that was real
    /// goes round again; one that only "woke" on an old hang-up is renewed.
    async fn idle(&self, watch: &Watch, hung_up: bool) -> io::Result<()> {
        if hung_up {
            self.renew(watch)?;
            // Never a loop without a pause, whatever the system says next.
            tokio::task::yield_now().await;
        }
        Ok(())
    }

    /// Reads what the shell wrote; 0 means it has ended.
    ///
    /// # Errors
    /// Fails on a read error other than the end of the shell.
    pub async fn read(&self, buf: &mut [u8]) -> io::Result<usize> {
        let mut waited = Duration::ZERO;
        loop {
            let watch = self.watch();
            let mut ready = watch.readable().await?;
            let hung_up = closed(&ready);
            match ready.try_io(|fd| Ok(rustix::io::read(fd, &mut *buf)?)) {
                // Linux answers EIO while nobody has the shell's side open:
                // once the shell has ended, but also for a moment before it
                // starts, when systemd has set the terminal up and closed it.
                Ok(Err(e)) if e.raw_os_error() == Some(rustix::io::Errno::IO.raw_os_error()) => {
                    if self.started.load(Ordering::Relaxed) || waited >= START_GRACE {
                        return Ok(0);
                    }
                    tokio::time::sleep(START_POLL).await;
                    waited += START_POLL;
                }
                Ok(done) => {
                    self.started.store(true, Ordering::Relaxed);
                    return done;
                }
                Err(_not_ready) => self.idle(&watch, hung_up).await?,
            }
        }
    }

    /// Writes all of `data` to the shell.
    ///
    /// # Errors
    /// Fails when the shell has ended.
    pub async fn write_all(&self, mut data: &[u8]) -> io::Result<()> {
        while !data.is_empty() {
            let watch = self.watch();
            let mut ready = watch.writable().await?;
            let hung_up = closed(&ready);
            match ready.try_io(|fd| Ok(rustix::io::write(fd, data)?)) {
                Ok(Ok(0)) => return Err(io::ErrorKind::WriteZero.into()),
                Ok(Ok(n)) => data = &data[n..],
                Ok(Err(e)) => return Err(e),
                Err(_not_ready) => self.idle(&watch, hung_up).await?,
            }
        }
        Ok(())
    }

    /// Tells the shell its window is now `cols` x `rows`.
    ///
    /// # Errors
    /// Fails when the descriptor is not a terminal.
    pub fn resize(&self, cols: u16, rows: u16) -> io::Result<()> {
        Ok(tcsetwinsize(self.watch().get_ref(), Winsize { ws_col: cols, ws_row: rows, ws_xpixel: 0, ws_ypixel: 0 })?)
    }
}

/// Has the runtime watch `fd`.
fn watched(fd: OwnedFd) -> io::Result<Watch> {
    // SAFETY: `fd` is an open descriptor that this `AsyncFd` owns from here
    // on, so it stays open and the same until the `AsyncFd` is dropped.
    Ok(Arc::new(unsafe { AsyncFd::register(fd) }?))
}

/// Whether the runtime remembers a hang-up on the descriptor.
fn closed(ready: &AsyncFdReadyGuard<'_, OwnedFd>) -> bool {
    ready.ready().is_read_closed() || ready.ready().is_write_closed()
}

#[cfg(test)]
mod tests {
    use rustix::pty::{OpenptFlags, grantpt, openpt, ptsname, unlockpt};

    use super::*;

    /// A pseudo-terminal: its master as a [`Pty`], and its other side open.
    fn pair() -> (Pty, std::fs::File) {
        let master = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY).unwrap();
        grantpt(&master).unwrap();
        unlockpt(&master).unwrap();
        let name = ptsname(&master, Vec::new()).unwrap();
        let side = std::fs::OpenOptions::new().read(true).write(true).open(name.to_str().unwrap()).unwrap();
        (Pty::new(master).unwrap(), side)
    }

    #[tokio::test]
    async fn a_terminal_watched_afresh_still_reads_writes_and_resizes() {
        use std::io::{Read, Write};
        let (pty, mut side) = pair();
        let first = pty.watch();
        pty.idle(&first, true).await.unwrap();
        assert!(!Arc::ptr_eq(&first, &pty.watch()), "watched through a new copy");
        // An old holder asking again changes nothing: it is no longer the one in use.
        let second = pty.watch();
        pty.renew(&first).unwrap();
        assert!(Arc::ptr_eq(&second, &pty.watch()));
        // A wait that was real is left alone.
        pty.idle(&second, false).await.unwrap();
        assert!(Arc::ptr_eq(&second, &pty.watch()));

        side.write_all(b"out\n").unwrap();
        let mut buf = [0u8; 64];
        let n = pty.read(&mut buf).await.unwrap();
        assert!(String::from_utf8_lossy(&buf[..n]).contains("out"));
        pty.write_all(b"in\n").await.unwrap();
        let mut got = [0u8; 8];
        let n = side.read(&mut got).unwrap();
        assert_eq!(&got[..n], b"in\n");
        pty.resize(100, 30).unwrap();
    }
}
