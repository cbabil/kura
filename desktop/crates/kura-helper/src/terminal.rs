//! What runs as the signed-in user: a login shell on a pseudo-terminal and
//! the file agent (`kura-agent`, ADR-031) on a socket, the other end going
//! to desktopd. systemd starts both, as `run0` does, outside the helper's
//! sandbox ([`systemd::SystemdShell`]). This module keeps count.

mod agents;
#[cfg(target_os = "linux")]
pub mod systemd;

use std::collections::HashMap;
use std::os::fd::OwnedFd;
use std::sync::{Arc, Mutex};

use kura_desktop_core::accounts::Account;
use kura_desktop_core::root::SysRoot;
use kura_desktop_core::session::new_session_id;
use kura_desktop_core::terminal::valid_size;

use crate::Fut;
use crate::refusal::Refusal;

/// Terminals one user may have open at once.
pub const MAX_PER_USER: usize = 8;

/// Starts and stops shells.
pub trait ShellLauncher: Send + Sync {
    /// Starts `account`'s login shell on a new pseudo-terminal of
    /// `cols` x `rows`; gives the master end and a handle for the shell.
    fn open<'a>(&'a self, account: &'a Account, cols: u16, rows: u16) -> Fut<'a, Result<(OwnedFd, String), String>>;
    /// Starts `account`'s file agent (`kura-agent`) with one end of a
    /// socket as its input and output; gives the other end and a handle.
    fn open_agent<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<(OwnedFd, String), String>>;
    /// True while the shell behind `handle` runs.
    fn running<'a>(&'a self, handle: &'a str) -> Fut<'a, bool>;
    /// Stops the shell. Stopping twice is fine.
    fn close<'a>(&'a self, handle: &'a str) -> Fut<'a, ()>;
    /// Stops every shell an earlier helper left behind (called at start,
    /// when no terminal can be open).
    fn sweep(&self) -> Fut<'_, ()>;
}

/// The id of what was started, and its end for desktopd.
pub type Started = (String, OwnedFd);

/// What runs as the user.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Shell,
    /// The file agent: one for each ticket.
    Agent,
}

struct Open {
    ticket: String,
    user: String,
    kind: Kind,
    /// The launcher's handle; `None` while the shell is being started.
    handle: Option<String>,
}

/// The open terminals and who owns them.
pub struct Terminals {
    launcher: Arc<dyn ShellLauncher>,
    root: SysRoot,
    open: Mutex<HashMap<String, Open>>,
}

impl Terminals {
    /// Terminals started by `launcher`; `/etc/shells` is read under `root`.
    pub fn new(launcher: Arc<dyn ShellLauncher>, root: SysRoot) -> Self {
        Self { launcher, root, open: Mutex::new(HashMap::new()) }
    }

    /// Opens a terminal for `account`, owned by `ticket`: its id and the
    /// pseudo-terminal's master end.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for a size out of range, [`Refusal::NoShell`]
    /// when the account's shell is not in `/etc/shells`, [`Refusal::Busy`]
    /// at [`MAX_PER_USER`], [`Refusal::Unavailable`] when it cannot start,
    /// [`Refusal::SignedOut`] when the ticket was signed out meanwhile.
    pub async fn open(&self, ticket: &str, account: &Account, cols: u16, rows: u16) -> Result<Started, Refusal> {
        if !valid_size(cols, rows) {
            return Err(Refusal::Invalid("terminal size".into()));
        }
        if !self.has_login_shell(&account.shell) {
            return Err(Refusal::NoShell);
        }
        self.forget_ended(&account.name, Kind::Shell).await;
        self.start(ticket, account, Kind::Shell, self.launcher.open(account, cols, rows)).await
    }

    /// Takes the user's slot first (parallel requests cannot pass the limit), then starts it.
    async fn start(
        &self,
        ticket: &str,
        account: &Account,
        kind: Kind,
        launch: Fut<'_, Result<(OwnedFd, String), String>>,
    ) -> Result<(String, OwnedFd), Refusal> {
        let id = new_session_id();
        {
            let mut open = self.lock();
            if open.values().filter(|o| o.user == account.name && o.kind == kind).count() >= MAX_PER_USER {
                return Err(Refusal::Busy);
            }
            let starting = Open { ticket: ticket.to_owned(), user: account.name.clone(), kind, handle: None };
            open.insert(id.clone(), starting);
        }
        let (end, handle) = match launch.await {
            Ok(started) => started,
            Err(why) => {
                self.lock().remove(&id);
                return Err(Refusal::Unavailable(why));
            }
        };
        // Signed out while systemd was starting it: it must not stay.
        let kept = self.lock().get_mut(&id).map(|o| o.handle = Some(handle.clone())).is_some();
        if !kept {
            self.launcher.close(&handle).await;
            return Err(Refusal::SignedOut);
        }
        Ok((id, end))
    }

    /// Closes the terminal or the file agent `id` if `ticket` opened it.
    ///
    /// # Errors
    /// [`Refusal::NotFound`] for an unknown id or someone else's terminal.
    pub async fn close(&self, ticket: &str, id: &str) -> Result<(), Refusal> {
        let closed = {
            let mut open = self.lock();
            if !open.get(id).is_some_and(|o| o.ticket == ticket) {
                return Err(Refusal::NotFound);
            }
            open.remove(id)
        };
        if let Some(handle) = closed.and_then(|o| o.handle) {
            self.launcher.close(&handle).await;
        }
        Ok(())
    }

    /// Closes every terminal and agent `ticket` opened (at sign-out).
    pub async fn close_all(&self, ticket: &str) {
        self.close_where(|o| o.ticket == ticket).await;
    }

    /// Closes everything `gone` says to.
    async fn close_where(&self, gone: impl Fn(&Open) -> bool) {
        let closed: Vec<Open> = {
            let mut open = self.lock();
            let ids: Vec<String> = open.iter().filter(|(_, o)| gone(o)).map(|(id, _)| id.clone()).collect();
            ids.iter().filter_map(|id| open.remove(id)).collect()
        };
        for handle in closed.into_iter().filter_map(|o| o.handle) {
            self.launcher.close(&handle).await;
        }
    }

    /// When `user` is at the limit for `kind`, drops the records of those
    /// that have ended on their own.
    async fn forget_ended(&self, user: &str, kind: Kind) {
        let of_user = |o: &Open| o.user == user && o.kind == kind;
        let started: Vec<(String, String)> = {
            let open = self.lock();
            if open.values().filter(|o| of_user(o)).count() < MAX_PER_USER {
                return;
            }
            open.iter()
                .filter(|(_, o)| of_user(o))
                .filter_map(|(id, o)| Some((id.clone(), o.handle.clone()?)))
                .collect()
        };
        for (id, handle) in started {
            if !self.launcher.running(&handle).await {
                self.lock().remove(&id);
            }
        }
    }

    /// True when `shell` is one of `/etc/shells`: an account with `nologin`
    /// or no shell gets no terminal, no Files and no Browser.
    pub fn has_login_shell(&self, shell: &str) -> bool {
        let shells = self.root.read("/etc/shells").unwrap_or_default();
        !shell.is_empty() && shells.lines().map(str::trim).any(|l| l == shell && !l.starts_with('#'))
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Open>> {
        kura_desktop_core::lock(&self.open)
    }
}
