//! A shell on a local pseudo-terminal, run as whoever runs desktopd. Only
//! in development builds and tests: on a device the helper asks systemd for
//! a shell as the signed-in user instead.

use std::collections::HashMap;
use std::io;
use std::os::fd::OwnedFd;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::Mutex;

use kura_desktop_core::accounts::Account;
use kura_desktop_core::session::new_session_id;
use kura_helper::Fut;
use kura_helper::terminal::ShellLauncher;
use rustix::io::{FdFlags, fcntl_setfd};
use rustix::pty::{OpenptFlags, grantpt, openpt, ptsname, unlockpt};
use rustix::termios::{Winsize, tcsetwinsize};

/// Starts `program` on a new pseudo-terminal of `cols` x `rows`; gives the
/// master end and the child.
///
/// # Errors
/// Fails when the pseudo-terminal cannot be made or the program not started.
pub fn spawn(program: &str, cols: u16, rows: u16) -> io::Result<(OwnedFd, Child)> {
    let master = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY)?;
    // Not every system takes CLOEXEC when opening; without it the shell
    // would inherit the master end and never see it close.
    fcntl_setfd(&master, FdFlags::CLOEXEC)?;
    grantpt(&master)?;
    unlockpt(&master)?;
    let name = ptsname(&master, Vec::new())?;
    let slave = std::fs::OpenOptions::new().read(true).write(true).open(name.to_string_lossy().as_ref())?;
    tcsetwinsize(&slave, Winsize { ws_col: cols, ws_row: rows, ws_xpixel: 0, ws_ypixel: 0 })?;
    let mut command = Command::new(program);
    command.stdin(slave.try_clone()?).stdout(slave.try_clone()?).stderr(slave).env("TERM", "xterm-256color");
    // SAFETY: between fork and exec only setsid and an ioctl run, both
    // async-signal-safe; they make the pseudo-terminal the shell's
    // controlling terminal so job control and Ctrl-C work.
    unsafe {
        command.pre_exec(|| {
            rustix::process::setsid()?;
            rustix::process::ioctl_tiocsctty(io::stdin())?;
            Ok(())
        });
    }
    Ok((master, command.spawn()?))
}

/// Shells of the person running desktopd, whoever the account is, and
/// file agents that see the development root as the whole disk.
pub struct LocalShell {
    program: String,
    root: PathBuf,
    running: Mutex<HashMap<String, Child>>,
}

impl LocalShell {
    /// Shells that run `program`; agents whose `/` is the folder `root`.
    pub fn new(program: &str, root: PathBuf) -> Self {
        Self { program: program.to_owned(), root, running: Mutex::default() }
    }

    /// Runs the file agent on a thread, for the home `/home/<name>` under
    /// the root (made with a first file when it is not there yet). The
    /// thread ends when the other end of the socket closes.
    fn start_agent(&self, name: &str) -> io::Result<OwnedFd> {
        let home = format!("/home/{name}");
        let real = self.root.join(home.trim_start_matches('/'));
        if !real.exists() {
            std::fs::create_dir_all(real.join("Documents"))?;
            std::fs::write(real.join("Welcome.txt"), "These are the development files.\n")?;
        }
        let (ours, theirs) = std::os::unix::net::UnixStream::pair()?;
        let mut from = theirs.try_clone()?;
        let agent = kura_agent::Agent::jailed(home, self.root.clone());
        std::thread::spawn(move || {
            let mut to = theirs;
            if let Err(e) = agent.serve(&mut from, &mut to) {
                tracing::debug!("the development file agent ended: {e}");
            }
        });
        Ok(ours.into())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Child>> {
        kura_desktop_core::lock(&self.running)
    }
}

impl ShellLauncher for LocalShell {
    fn open<'a>(&'a self, _account: &'a Account, cols: u16, rows: u16) -> Fut<'a, Result<(OwnedFd, String), String>> {
        let started = spawn(&self.program, cols, rows).map_err(|e| e.to_string()).map(|(master, child)| {
            let handle = new_session_id();
            self.lock().insert(handle.clone(), child);
            (master, handle)
        });
        Box::pin(async move { started })
    }

    fn open_agent<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<(OwnedFd, String), String>> {
        let started =
            self.start_agent(&account.name).map(|socket| (socket, new_session_id())).map_err(|e| e.to_string());
        Box::pin(async move { started })
    }

    fn running<'a>(&'a self, handle: &'a str) -> Fut<'a, bool> {
        let running = self.lock().get_mut(handle).is_some_and(|child| matches!(child.try_wait(), Ok(None)));
        Box::pin(async move { running })
    }

    fn close<'a>(&'a self, handle: &'a str) -> Fut<'a, ()> {
        if let Some(mut child) = self.lock().remove(handle) {
            // Killed or already gone, the shell is reaped either way.
            let _ = child.kill();
            let _ = child.wait();
        }
        Box::pin(async {})
    }

    fn sweep(&self) -> Fut<'_, ()> {
        Box::pin(async {})
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use super::*;

    /// A shell that held the master end itself would outlive desktopd.
    #[test]
    fn the_shell_ends_when_the_master_end_closes() {
        let (master, mut child) = spawn("/bin/sh", 80, 24).unwrap();
        assert!(child.try_wait().unwrap().is_none(), "running while the terminal is open");
        drop(master);
        let deadline = Instant::now() + Duration::from_secs(10);
        while child.try_wait().unwrap().is_none() {
            assert!(Instant::now() < deadline, "the shell is still running");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    #[test]
    fn a_missing_program_is_an_error() {
        assert!(spawn("/nonexistent-kura/sh", 80, 24).is_err());
    }
}
