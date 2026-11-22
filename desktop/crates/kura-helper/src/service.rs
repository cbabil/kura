//! What the helper does, without D-Bus: each method checks the ticket and
//! the action's rule ([`Gate`]), validates its input, does the one thing and
//! writes who did it to the journal. Sign-in and terminals are here;
//! everything asked by name ([`Service::ask`]) is in `actions.rs`.

mod actions;
mod catalog;
mod settings;

use std::os::fd::OwnedFd;
use std::sync::Arc;
use std::time::Instant;

use kura_desktop_core::accounts::Account;
use kura_desktop_core::auth::{AuthOutcome, valid_user_name};
use kura_desktop_core::ratelimit::RateLimiter;
use kura_desktop_core::root::SysRoot;
use zeroize::Zeroizing;

use crate::apps::Apps;
use crate::authenticate::Authenticator;
use crate::docker::Docker;
use crate::journal::Journal;
use crate::machine::Machine;
use crate::policy::{Action, Gate};
use crate::refusal::Refusal;
use crate::system::System;
use crate::terminal::{ShellLauncher, Terminals};

/// Docker, the journal, the shell launcher and the machine the service uses.
pub struct Backends {
    pub docker: Arc<dyn Docker>,
    pub journal: Arc<dyn Journal>,
    pub shells: Arc<dyn ShellLauncher>,
    pub machine: Arc<dyn Machine>,
    pub system: Arc<dyn System>,
    pub apps: Arc<dyn Apps>,
}

/// Requests to Docker, the journal and apt in flight at most; more are
/// refused as busy, so a flood of them cannot hold up sign-ins.
pub const SLOTS: usize = 4;

/// The helper's actions.
pub struct Service {
    auth: Arc<Authenticator>,
    /// Wrong passwords per user, counted here too: desktopd's own limit
    /// does not bind a desktopd that has been taken over.
    failures: RateLimiter,
    slots: tokio::sync::Semaphore,
    /// Held while an update job is looked at and started: one at a time.
    starting: tokio::sync::Mutex<()>,
    /// Held while a setting changes: the root command's own checks (the
    /// last administrator) and its file edits are not made for two at once.
    changing: tokio::sync::Mutex<()>,
    gate: Gate,
    docker: Arc<dyn Docker>,
    journal: Arc<dyn Journal>,
    machine: Arc<dyn Machine>,
    system: Arc<dyn System>,
    apps: Arc<dyn Apps>,
    root: SysRoot,
    terminals: Terminals,
}

fn json<T: serde::Serialize>(value: &T) -> Result<String, Refusal> {
    serde_json::to_string(value).map_err(|e| Refusal::Unavailable(e.to_string()))
}

impl Service {
    /// A service reading accounts and shells under `root`.
    pub fn new(auth: Arc<Authenticator>, root: SysRoot, backends: Backends) -> Self {
        Self {
            auth,
            failures: RateLimiter::new(),
            slots: tokio::sync::Semaphore::new(SLOTS),
            starting: tokio::sync::Mutex::new(()),
            changing: tokio::sync::Mutex::new(()),
            gate: Gate::new(root.clone()),
            docker: backends.docker,
            journal: backends.journal,
            machine: backends.machine,
            system: backends.system,
            apps: backends.apps,
            terminals: Terminals::new(backends.shells, root.clone()),
            root,
        }
    }

    /// The gate, with the refusal logged.
    fn admit(&self, ticket: &str, action: Action) -> Result<Account, Refusal> {
        self.gate.check(ticket, action, Instant::now()).inspect_err(|why| tracing::warn!(?action, %why, "refused"))
    }

    /// One of the few slots for a request to Docker or the journal.
    fn slot(&self) -> Result<tokio::sync::SemaphorePermit<'_>, Refusal> {
        self.slots.try_acquire().map_err(|_| Refusal::Busy)
    }

    /// Checks a password, without signing anybody in. After five wrong
    /// passwords in a minute for a user, further ones are refused
    /// unchecked. The password is wiped afterwards.
    pub(crate) async fn verify(&self, user: &str, password: Zeroizing<String>) -> AuthOutcome {
        let shown = if valid_user_name(user) { user } else { "(invalid)" };
        let Ok(attempt) = self.failures.begin(vec![format!("user:{shown}")], Instant::now()) else {
            tracing::warn!(user = shown, "authenticate: too many wrong passwords");
            return AuthOutcome::Wrong;
        };
        let (auth, name) = (self.auth.clone(), user.to_owned());
        let check = tokio::task::spawn_blocking(move || auth.authenticate(&name, &password));
        let outcome = check.await.unwrap_or_else(|e| {
            tracing::error!("password check failed: {e}");
            AuthOutcome::Wrong
        });
        if outcome != AuthOutcome::Wrong {
            self.failures.succeeded(attempt);
        }
        tracing::info!(user = shown, ok = matches!(outcome, AuthOutcome::Ok { .. }), "authenticate");
        outcome
    }

    /// Checks a password; a success comes with a new ticket, anything else
    /// with an empty one.
    pub async fn authenticate(&self, user: String, password: Zeroizing<String>) -> (AuthOutcome, String) {
        let outcome = self.verify(&user, password).await;
        let ok = matches!(outcome, AuthOutcome::Ok { .. });
        (outcome, if ok { self.gate.sign_in(&user, Instant::now()) } else { String::new() })
    }

    /// Marks a ticket used.
    ///
    /// # Errors
    /// [`Refusal::SignedOut`] when it has ended.
    pub fn keep_alive(&self, ticket: &str) -> Result<(), Refusal> {
        self.gate.keep_alive(ticket, Instant::now())
    }

    /// Ends a ticket and closes the terminals it opened.
    pub async fn sign_out(&self, ticket: &str) {
        if let Some(user) = self.gate.sign_out(ticket) {
            tracing::info!(user, "sign out");
        }
        self.terminals.close_all(ticket).await;
    }

    /// Starts the user's login shell: the terminal's id and its master end.
    ///
    /// # Errors
    /// See [`Terminals::open`] and [`Gate::check`].
    pub async fn open_terminal(&self, ticket: &str, cols: u16, rows: u16) -> Result<(String, OwnedFd), Refusal> {
        let account = self.admit(ticket, Action::Terminal)?;
        let opened = self.terminals.open(ticket, &account, cols, rows).await;
        tracing::info!(user = account.name, ok = opened.is_ok(), "open terminal");
        opened
    }

    /// Starts the ticket's user their file agent: its id and the socket to
    /// it. Every signed-in person has their own files.
    ///
    /// # Errors
    /// See [`Terminals::open_agent`].
    pub async fn open_files(&self, ticket: &str) -> Result<(String, OwnedFd), Refusal> {
        let account = self.admit(ticket, Action::Files)?;
        let opened = self.terminals.open_agent(ticket, &account).await;
        tracing::info!(user = account.name, ok = opened.is_ok(), "open files");
        opened
    }

    /// Stops a terminal or a file agent the ticket opened.
    ///
    /// # Errors
    /// [`Refusal::NotFound`] for any other.
    pub async fn close_terminal(&self, ticket: &str, id: &str) -> Result<(), Refusal> {
        self.terminals.close(ticket, id).await
    }
}

#[cfg(test)]
pub(crate) mod tests;
#[cfg(test)]
mod tests_actions;
#[cfg(test)]
mod tests_catalog;
#[cfg(test)]
mod tests_files;
#[cfg(test)]
mod tests_settings;
