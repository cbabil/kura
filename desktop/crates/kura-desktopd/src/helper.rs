//! What desktopd asks of `kura-helper` over the system D-Bus: password
//! checks, terminals, and by name everything else: Docker, the journal,
//! updates and power ([`dbus::DbusHelper`]). A
//! stand-in serves development on a Mac (`dev-auth` feature) and the tests
//! ([`dev::DevHelper`]). Every method but `authenticate` takes the ticket
//! the helper gave at sign-in.

pub mod dbus;
#[cfg(any(test, feature = "dev-auth"))]
pub mod dev;

use std::future::Future;
use std::os::fd::OwnedFd;
use std::pin::Pin;

use kura_desktop_core::actions::Action;
use kura_desktop_core::auth::AuthOutcome;
use kura_desktop_core::refusal::Refused;

pub use dbus::DbusHelper;
#[cfg(any(test, feature = "dev-auth"))]
pub use dev::{DEV_PASSWORD, DevHelper};

/// The boxed future a [`Helper`] returns.
pub type Fut<'a, T> = Pin<Box<dyn Future<Output = Result<T, HelperError>> + Send + 'a>>;

/// The helper's side of Kura Desktop.
pub trait Helper: Send + Sync {
    /// Asks whether `password` is right for `user`; a success comes with
    /// the ticket for everything else.
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> Fut<'a, (AuthOutcome, String)>;
    /// Marks the ticket used, for a session that is open but asks nothing
    /// of the helper (it would otherwise end after 12 hours).
    fn keep_alive<'a>(&'a self, ticket: &'a str) -> Fut<'a, ()>;
    /// Ends a ticket and the terminals opened with it.
    fn sign_out<'a>(&'a self, ticket: &'a str) -> Fut<'a, ()>;
    /// Starts the user's shell: the terminal's id and its master end.
    fn open_terminal<'a>(&'a self, ticket: &'a str, cols: u16, rows: u16) -> Fut<'a, (String, OwnedFd)>;
    /// Starts the user's file agent: its id and the socket to it.
    fn open_files<'a>(&'a self, ticket: &'a str) -> Fut<'a, (String, OwnedFd)>;
    /// Stops a terminal or a file agent.
    fn close_terminal<'a>(&'a self, ticket: &'a str, id: &'a str) -> Fut<'a, ()>;
    /// Does one of the helper's named actions with its JSON arguments
    /// (see [`ask`]); the answer is JSON, or empty.
    fn ask<'a>(&'a self, ticket: &'a str, action: Action, args: String) -> Fut<'a, String>;
}

/// Asks the helper for `action` with `args`, one of the argument types of
/// `kura_desktop_core::actions` (or `()` for none).
pub async fn ask(
    helper: &dyn Helper,
    ticket: &str,
    action: Action,
    args: &impl serde::Serialize,
) -> Result<String, HelperError> {
    let args = serde_json::to_string(args).map_err(|_| HelperError::Invalid)?;
    helper.ask(ticket, action, args).await
}

/// Why the helper did not do it.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HelperError {
    /// The ticket is no longer good: the user must sign in again.
    #[error("not signed in")]
    SignedOut,
    #[error("administrators only")]
    Admin,
    #[error("invalid request")]
    Invalid,
    #[error("not found")]
    NotFound,
    #[error("no login shell")]
    NoShell,
    #[error("too many at once")]
    Busy,
    /// The helper, Docker, the journal or systemd did not answer.
    #[error("kura-helper unavailable: {0}")]
    Unavailable(String),
}

impl From<zbus::Error> for HelperError {
    /// The helper's refusals travel as its own D-Bus errors
    /// ([`Refused`]); any other error, the bus's own included, means the
    /// helper could not be asked.
    fn from(e: zbus::Error) -> Self {
        let refused = match &e {
            zbus::Error::MethodError(name, _, _) => Refused::from_error_name(name.as_str()),
            _ => None,
        };
        match refused {
            Some(kind) => Self::from_refused(kind, &e.to_string()),
            None => Self::Unavailable(e.to_string()),
        }
    }
}

impl HelperError {
    /// The error for one of the helper's refusals; `detail` says what did
    /// not answer when that is the refusal.
    pub fn from_refused(kind: Refused, detail: &str) -> Self {
        match kind {
            Refused::SignedOut => Self::SignedOut,
            Refused::Admin => Self::Admin,
            Refused::Invalid => Self::Invalid,
            Refused::NotFound => Self::NotFound,
            Refused::NoShell => Self::NoShell,
            Refused::Busy => Self::Busy,
            Refused::Unavailable => Self::Unavailable(detail.to_owned()),
        }
    }
}

#[cfg(test)]
mod tests;
