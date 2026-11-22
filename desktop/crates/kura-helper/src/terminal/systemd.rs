//! The real [`ShellLauncher`]: a transient systemd service per terminal,
//! which is how `run0` starts a shell. systemd, not the helper, forks the
//! shell, so it runs as the user (`User=`), in a login session of its own
//! (`PAMName=login`), with the pseudo-terminal as its controlling terminal,
//! and outside the helper's sandbox. Proven by the Linux CI jobs.

use std::os::fd::OwnedFd;

use kura_desktop_core::accounts::Account;
use kura_desktop_core::session::new_session_id;
use rustix::pty::{OpenptFlags, grantpt, openpt, ptsname, unlockpt};
use rustix::termios::{Winsize, tcsetwinsize};
use zbus::Variant as Value;

use super::ShellLauncher;
use crate::Fut;
use crate::systemd::{ManagerProxy, Property};

/// What every terminal's and every file agent's unit is called.
const UNITS: [&str; 2] = ["kura-terminal-*.service", "kura-files-*.service"];
/// The most memory and tasks one agent may take.
const AGENT_MEMORY_MAX: u64 = 256 * 1024 * 1024;
const AGENT_TASKS_MAX: u64 = 16;
/// The file agent, in the image.
const AGENT: &str = "/usr/lib/kura/kura-agent";

/// Starts shells through systemd's manager on the system bus.
pub struct SystemdShell {
    manager: ManagerProxy<'static>,
}

impl SystemdShell {
    /// Uses `conn`, the helper's own connection to the system bus.
    ///
    /// # Errors
    /// Fails when the proxy cannot be set up.
    pub async fn new(conn: &zbus::Connection) -> zbus::Result<Self> {
        Ok(Self { manager: ManagerProxy::new(conn).await? })
    }

    async fn start(&self, account: &Account, cols: u16, rows: u16) -> Result<(OwnedFd, String), String> {
        let io = |e: rustix::io::Errno| format!("pseudo-terminal: {e}");
        let master = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY | OpenptFlags::CLOEXEC).map_err(io)?;
        grantpt(&master).map_err(io)?;
        unlockpt(&master).map_err(io)?;
        let size = Winsize { ws_col: cols, ws_row: rows, ws_xpixel: 0, ws_ypixel: 0 };
        tcsetwinsize(&master, size).map_err(io)?;
        let tty = ptsname(&master, Vec::new()).map_err(io)?.to_string_lossy().into_owned();

        let unit = format!("kura-terminal-{}.service", &new_session_id()[..16]);
        // A leading "-" in argv[0] makes it a login shell, as login(1) does.
        let name = account.shell.rsplit('/').next().unwrap_or("sh");
        let exec = vec![(account.shell.clone(), vec![format!("-{name}")], false)];
        let properties: Vec<Property<'_>> = vec![
            ("Description", Value::from(format!("Kura Desktop terminal of {}", account.name))),
            ("User", Value::from(account.name.as_str())),
            ("PAMName", Value::from("login")),
            ("WorkingDirectory", Value::from("~")),
            ("Environment", Value::from(vec!["TERM=xterm-256color"])),
            ("StandardInput", Value::from("tty")),
            ("StandardOutput", Value::from("tty")),
            ("StandardError", Value::from("tty")),
            ("TTYPath", Value::from(tty)),
            ("SendSIGHUP", Value::from(true)),
            ("CollectMode", Value::from("inactive-or-failed")),
            ("ExecStart", Value::from(exec)),
        ];
        self.manager
            .start_transient_unit(&unit, "fail", &properties, &[])
            .await
            .map_err(|e| format!("systemd: {e}"))?;
        Ok((master, unit))
    }
}

impl SystemdShell {
    /// Starts the file agent as `account`, its input and output one end of
    /// a socket whose other end is returned. No session, no terminal, and
    /// no way to gain rights: it is the user's own hands on their files.
    async fn start_agent(&self, account: &Account) -> Result<(OwnedFd, String), String> {
        use rustix::net::{AddressFamily, SocketFlags, SocketType, socketpair};
        let (ours, theirs) = socketpair(AddressFamily::UNIX, SocketType::STREAM, SocketFlags::CLOEXEC, None)
            .map_err(|e| format!("socket: {e}"))?;
        let unit = format!("kura-files-{}.service", &new_session_id()[..16]);
        let exec = vec![(AGENT.to_owned(), vec!["kura-agent".to_owned()], false)];
        let end = || Value::from(zbus::Fd::from(std::os::fd::AsFd::as_fd(&theirs)));
        let properties: Vec<Property<'_>> = vec![
            ("Description", Value::from(format!("Kura Desktop files of {}", account.name))),
            ("User", Value::from(account.name.as_str())),
            ("WorkingDirectory", Value::from("~")),
            ("StandardInputFileDescriptor", end()),
            ("StandardOutputFileDescriptor", end()),
            ("StandardError", Value::from("journal")),
            ("NoNewPrivileges", Value::from(true)),
            // No capability whatever the account, and bounds a login
            // session would give it through its user slice.
            ("CapabilityBoundingSet", Value::from(0u64)),
            ("MemoryMax", Value::from(AGENT_MEMORY_MAX)),
            ("TasksMax", Value::from(AGENT_TASKS_MAX)),
            ("CollectMode", Value::from("inactive-or-failed")),
            ("ExecStart", Value::from(exec)),
        ];
        self.manager
            .start_transient_unit(&unit, "fail", &properties, &[])
            .await
            .map_err(|e| format!("systemd: {e}"))?;
        Ok((ours, unit))
    }
}

impl ShellLauncher for SystemdShell {
    fn open_agent<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<(OwnedFd, String), String>> {
        Box::pin(self.start_agent(account))
    }

    fn open<'a>(&'a self, account: &'a Account, cols: u16, rows: u16) -> Fut<'a, Result<(OwnedFd, String), String>> {
        Box::pin(self.start(account, cols, rows))
    }

    fn running<'a>(&'a self, handle: &'a str) -> Fut<'a, bool> {
        // An ended unit is collected, so systemd no longer knows its name.
        Box::pin(async move { self.manager.get_unit(handle).await.is_ok() })
    }

    fn sweep(&self) -> Fut<'_, ()> {
        Box::pin(async {
            let units = self.manager.list_units_by_patterns(&[], &UNITS).await.unwrap_or_default();
            for (name, ..) in units {
                tracing::warn!("stopping {name}, left by an earlier helper");
                self.close(&name).await;
            }
        })
    }

    fn close<'a>(&'a self, handle: &'a str) -> Fut<'a, ()> {
        Box::pin(async move {
            // "No such unit" is the usual answer: the shell had already ended.
            if let Err(e) = self.manager.stop_unit(handle, "replace").await {
                tracing::debug!("stopping {handle}: {e}");
            }
        })
    }
}
