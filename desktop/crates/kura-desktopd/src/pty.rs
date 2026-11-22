//! The master end of a terminal's pseudo-terminal, as the helper hands it
//! over: non-blocking reads and writes for the WebSocket relay, and resizes.

use std::io;
use std::os::fd::OwnedFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use rustix::fs::{OFlags, fcntl_getfl, fcntl_setfl};
use rustix::termios::{Winsize, tcsetwinsize};
use tokio::io::unix::AsyncFd;

/// How long a new shell has to open its side of the pseudo-terminal.
const START_GRACE: Duration = Duration::from_secs(5);
/// How often that is looked at meanwhile.
const START_POLL: Duration = Duration::from_millis(50);

/// A pseudo-terminal's master end.
pub struct Pty {
    fd: AsyncFd<OwnedFd>,
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
        // SAFETY: `master` is an open descriptor that this `AsyncFd` owns from
        // here on, so it stays open and the same until the `AsyncFd` is dropped.
        Ok(Self { fd: unsafe { AsyncFd::register(master) }?, started: AtomicBool::new(false) })
    }

    /// Reads what the shell wrote; 0 means it has ended.
    ///
    /// # Errors
    /// Fails on a read error other than the end of the shell.
    pub async fn read(&self, buf: &mut [u8]) -> io::Result<usize> {
        let mut waited = Duration::ZERO;
        loop {
            let mut ready = self.fd.readable().await?;
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
                Err(_not_ready) => {}
            }
        }
    }

    /// Writes all of `data` to the shell.
    ///
    /// # Errors
    /// Fails when the shell has ended.
    pub async fn write_all(&self, mut data: &[u8]) -> io::Result<()> {
        while !data.is_empty() {
            let mut ready = self.fd.writable().await?;
            match ready.try_io(|fd| Ok(rustix::io::write(fd, data)?)) {
                Ok(Ok(0)) => return Err(io::ErrorKind::WriteZero.into()),
                Ok(Ok(n)) => data = &data[n..],
                Ok(Err(e)) => return Err(e),
                Err(_not_ready) => {}
            }
        }
        Ok(())
    }

    /// Tells the shell its window is now `cols` x `rows`.
    ///
    /// # Errors
    /// Fails when the descriptor is not a terminal.
    pub fn resize(&self, cols: u16, rows: u16) -> io::Result<()> {
        Ok(tcsetwinsize(&self.fd, Winsize { ws_col: cols, ws_row: rows, ws_xpixel: 0, ws_ypixel: 0 })?)
    }
}
