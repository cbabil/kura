//! The D-Bus object `/io/kura/Helper` with interface `io.kura.Helper1` (the 1
//! versions the interface), owned as `io.kura.Helper`. The bus policy lets
//! only `kura-desktop` call it, and the helper checks the caller's uid again
//! on every call. Sign-in and terminals have methods of their own; every
//! other action of [`crate::policy::Action`] goes through `Ask` by name.
//! All are done by [`Service`]; refusals travel as the helper's own D-Bus errors
//! ([`crate::refusal::HelperError`]).

use std::sync::Arc;

use zbus::OwnedFd;
use zbus::message::Header;
use zeroize::Zeroizing;

use crate::refusal::HelperError;
use crate::service::Service;

type Result<T> = std::result::Result<T, HelperError>;

/// The helper's well-known name on the system bus.
pub const BUS_NAME: &str = "io.kura.Helper";
/// The helper's object path.
pub const OBJECT_PATH: &str = "/io/kura/Helper";

/// The served object.
pub struct HelperIface {
    service: Arc<Service>,
    /// The only uid allowed to call, checked with the bus on every call on
    /// top of the bus policy; `None` on a private peer-to-peer connection.
    caller: Option<u32>,
}

impl HelperIface {
    /// Serves `service` over D-Bus to callers running as `caller`.
    pub fn new(service: Arc<Service>, caller: Option<u32>) -> Self {
        Self { service, caller }
    }

    /// Refuses a message whose sender does not run as the allowed uid.
    async fn admit(&self, conn: &zbus::Connection, hdr: &Header<'_>) -> Result<()> {
        let Some(allowed) = self.caller else { return Ok(()) };
        let uid = async {
            let sender = hdr.sender().ok_or(zbus::Error::MissingField)?.to_owned();
            let bus = zbus::fdo::DBusProxy::new(conn).await?;
            Ok::<u32, zbus::Error>(bus.get_connection_unix_user(sender.into()).await?)
        };
        match uid.await {
            Ok(uid) if uid == allowed => Ok(()),
            other => {
                tracing::warn!(member = ?hdr.member(), "refused a call from {other:?}");
                Err(HelperError::Caller("only kura-desktopd may call this".into()))
            }
        }
    }
}

#[zbus::interface(name = "io.kura.Helper1")]
impl HelperIface {
    /// Checks a password: `(ok, reason, admin, ticket)`, where reason is "",
    /// "wrong" or "expired" and the ticket is what every other method needs.
    async fn authenticate(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        user: String,
        password: String,
    ) -> Result<(bool, String, bool, String)> {
        let password = Zeroizing::new(password);
        self.admit(conn, &hdr).await?;
        let (outcome, ticket) = self.service.authenticate(user, password).await;
        let (ok, reason, admin) = outcome.to_wire();
        Ok((ok, reason, admin, ticket))
    }

    /// Marks a ticket used, for a session that is open but asks nothing.
    async fn keep_alive(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        ticket: String,
    ) -> Result<()> {
        self.admit(conn, &hdr).await?;
        Ok(self.service.keep_alive(&ticket)?)
    }

    /// Ends a ticket and the terminals it opened.
    async fn sign_out(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        ticket: String,
    ) -> Result<()> {
        self.admit(conn, &hdr).await?;
        self.service.sign_out(&ticket).await;
        Ok(())
    }

    /// Starts the ticket's user a login shell: the terminal's id and the
    /// master end of its pseudo-terminal.
    async fn open_terminal(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        ticket: String,
        cols: u16,
        rows: u16,
    ) -> Result<(String, OwnedFd)> {
        self.admit(conn, &hdr).await?;
        let (id, master) = self.service.open_terminal(&ticket, cols, rows).await?;
        Ok((id, master.into()))
    }

    /// Starts the ticket's user their file agent: its id (which
    /// `CloseTerminal` takes) and the socket to it.
    async fn open_files(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        ticket: String,
    ) -> Result<(String, OwnedFd)> {
        self.admit(conn, &hdr).await?;
        let (id, socket) = self.service.open_files(&ticket).await?;
        Ok((id, socket.into()))
    }

    /// Stops a terminal or a file agent the ticket opened.
    async fn close_terminal(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        ticket: String,
        id: String,
    ) -> Result<()> {
        self.admit(conn, &hdr).await?;
        Ok(self.service.close_terminal(&ticket, &id).await?)
    }

    /// Does the action called `action` (`kura_desktop_core::actions`) with
    /// its JSON arguments: containers, the journal, updates, power. The
    /// answer is JSON, or empty.
    async fn ask(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        ticket: String,
        action: String,
        args: String,
    ) -> Result<String> {
        self.admit(conn, &hdr).await?;
        Ok(self.service.ask(&ticket, &action, &args).await?)
    }
}

#[cfg(test)]
mod tests;
