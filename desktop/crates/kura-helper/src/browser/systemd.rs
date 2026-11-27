//! The real [`Browsers`]: a transient unit per person, as for terminals and
//! file agents. The unit's runtime folder is the person's own, so what is
//! at the socket's path is theirs to change: the helper, which is root,
//! checks who listens on what it reached (`SO_PEERCRED`) and hands over
//! only a server run as that person. Proven by the Linux CI jobs.

use std::os::fd::OwnedFd;
use std::time::{Duration, Instant};

use kura_desktop_core::accounts::Account;
use kura_desktop_core::browser::{COMMAND, runtime_dir, socket, unit};
use zbus::Variant as Value;

use super::Browsers;
use crate::Fut;
use crate::systemd::{DESCRIBED, ManagerProxy, Property};

/// How long a browser that was just started has to listen.
const START_WAIT: Duration = Duration::from_secs(15);
const RETRY: Duration = Duration::from_millis(200);
const MEMORY_MAX: u64 = 2 * 1024 * 1024 * 1024;
/// Chromium runs some 20-30 threads a tab.
const TASKS_MAX: u64 = 2048;
/// A stop gives Chromium this long to save its session.
const STOP_TIMEOUT: Duration = Duration::from_secs(20);

/// Starts browsers through systemd's manager on the system bus.
pub struct SystemdBrowsers {
    manager: ManagerProxy<'static>,
}

impl SystemdBrowsers {
    /// Uses `conn`, the helper's own connection to the system bus.
    ///
    /// # Errors
    /// Fails when the proxy cannot be set up.
    pub async fn new(conn: &zbus::Connection) -> zbus::Result<Self> {
        Ok(Self { manager: ManagerProxy::new(conn).await? })
    }

    async fn start(&self, account: &Account) -> Result<(), String> {
        let exec = vec![(COMMAND.to_owned(), vec!["kura-browser".to_owned(), "run".to_owned()], false)];
        // The loopback addresses, as systemd's IPAddressDeny= takes them.
        let loopback: Vec<(i32, Vec<u8>, u32)> = vec![
            (libc::AF_INET, vec![127, 0, 0, 0], 8),
            (libc::AF_INET6, std::net::Ipv6Addr::LOCALHOST.octets().to_vec(), 128),
        ];
        let properties: Vec<Property<'_>> = vec![
            ("Description", Value::from(format!("{} browser of {}", DESCRIBED, account.name))),
            ("User", Value::from(account.name.as_str())),
            ("WorkingDirectory", Value::from("~")),
            ("RuntimeDirectory", Value::from(vec![runtime_dir(&account.name)])),
            ("RuntimeDirectoryMode", Value::from(0o700u32)),
            ("UMask", Value::from(0o077u32)),
            ("StandardOutput", Value::from("journal")),
            ("StandardError", Value::from("journal")),
            ("NoNewPrivileges", Value::from(true)),
            ("CapabilityBoundingSet", Value::from(0u64)),
            // The X server's path socket in a /tmp of its own (its abstract
            // socket is guarded by the command's -nopn and the cookie)
            ("PrivateTmp", Value::from(true)),
            // The system read-only; their home stays theirs to write (the profile, downloads)
            ("ProtectSystem", Value::from("full")),
            ("IPAddressDeny", Value::from(loopback)),
            ("MemoryMax", Value::from(MEMORY_MAX)),
            ("TasksMax", Value::from(TASKS_MAX)),
            // A stop signals the command alone, which closes Chromium first
            ("KillMode", Value::from("mixed")),
            ("TimeoutStopUSec", Value::from(STOP_TIMEOUT.as_micros() as u64)),
            ("CollectMode", Value::from("inactive-or-failed")),
            ("ExecStart", Value::from(exec)),
        ];
        self.manager
            .start_transient_unit(&unit(&account.name), "fail", &properties, &[])
            .await
            .map(|_| ())
            .map_err(|e| format!("systemd: {e}"))
    }

    async fn open(&self, account: &Account) -> Result<OwnedFd, String> {
        if let Some(fd) = reach(account).await {
            return Ok(fd);
        }
        self.start(account).await?;
        let until = Instant::now() + START_WAIT;
        while Instant::now() < until {
            tokio::time::sleep(RETRY).await;
            if let Some(fd) = reach(account).await {
                return Ok(fd);
            }
            // Ended already (a missing keymap, a refused option): say so now.
            if self.manager.get_unit(&unit(&account.name)).await.is_err() {
                return Err("the browser ended as it started".into());
            }
        }
        Err("the browser did not start listening".into())
    }
}

/// A connection to `account`'s VNC socket, if one is there and is served by
/// a process of `account`'s own.
async fn reach(account: &Account) -> Option<OwnedFd> {
    let stream = tokio::net::UnixStream::connect(socket(&account.name)).await.ok()?.into_std().ok()?;
    match served_by(&stream, account.uid) {
        Ok(()) => Some(stream.into()),
        Err(why) => {
            tracing::warn!(user = account.name, "refused to hand over the browser socket: {why}");
            None
        }
    }
}

/// Ok when the server at the other end of `stream` runs as `uid`.
pub(crate) fn served_by(stream: &std::os::unix::net::UnixStream, uid: u32) -> Result<(), String> {
    let peer = rustix::net::sockopt::socket_peercred(stream).map_err(|e| format!("peer: {e}"))?;
    let theirs = peer.uid.as_raw();
    if theirs == uid { Ok(()) } else { Err(format!("served by uid {theirs}, not {uid}")) }
}

impl Browsers for SystemdBrowsers {
    fn open<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<OwnedFd, String>> {
        Box::pin(self.open(account))
    }

    fn stop<'a>(&'a self, user: &'a str) -> Fut<'a, ()> {
        Box::pin(async move {
            if let Err(e) = self.manager.stop_unit(&unit(user), "replace").await {
                tracing::debug!("stopping the browser of {user}: {e}");
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_server_of_the_account_itself_is_handed_over() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vnc.sock");
        let _listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        let stream = std::os::unix::net::UnixStream::connect(&path).unwrap();
        let me = unsafe { libc::getuid() };
        assert_eq!(served_by(&stream, me), Ok(()));
        assert!(served_by(&stream, me + 1).is_err(), "another person's, or root's, socket");
    }
}
