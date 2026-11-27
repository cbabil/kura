//! Each person's Browser (ADR-036): Chromium in TigerVNC's X server, run as
//! that person by systemd (`browser-<user>.service`), outside the
//! helper's sandbox, with its profile in their home. The helper starts it
//! when it is not running, connects to its VNC socket and hands desktopd
//! the connection ([`systemd::SystemdBrowsers`]).

#[cfg(target_os = "linux")]
pub mod systemd;

use std::os::fd::OwnedFd;

use kura_desktop_core::accounts::Account;

use crate::Fut;

/// Starts, reaches and stops people's browsers.
pub trait Browsers: Send + Sync {
    /// A connection to `account`'s browser, started first when it is not
    /// running. Only a server run as `account` itself is ever handed over.
    fn open<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<OwnedFd, String>>;
    /// Stops `user`'s browser; one that is not running is fine.
    fn stop<'a>(&'a self, user: &'a str) -> Fut<'a, ()>;
}
