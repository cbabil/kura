//! `kura-helper` over a D-Bus connection.

use std::os::fd::OwnedFd;

use kura_desktop_core::actions::Action;
use kura_desktop_core::auth::AuthOutcome;

use super::{Fut, Helper, HelperError};

#[zbus::proxy(interface = "io.kura.Helper1", default_service = "io.kura.Helper", default_path = "/io/kura/Helper")]
trait Helper1 {
    fn authenticate(&self, user: &str, password: &str) -> zbus::Result<(bool, String, bool, String)>;
    fn keep_alive(&self, ticket: &str) -> zbus::Result<()>;
    fn sign_out(&self, ticket: &str) -> zbus::Result<()>;
    fn open_terminal(&self, ticket: &str, cols: u16, rows: u16) -> zbus::Result<(String, zbus::OwnedFd)>;
    fn open_files(&self, ticket: &str) -> zbus::Result<(String, zbus::OwnedFd)>;
    fn close_terminal(&self, ticket: &str, id: &str) -> zbus::Result<()>;
    fn ask(&self, ticket: &str, action: &str, args: &str) -> zbus::Result<String>;
}

/// The helper on the system bus (or on a peer connection in tests).
pub struct DbusHelper {
    proxy: Helper1Proxy<'static>,
}

impl DbusHelper {
    /// Uses an open connection (the system bus, or a peer in tests).
    ///
    /// # Errors
    /// Fails when the proxy cannot be set up on the connection.
    pub async fn new(conn: &zbus::Connection) -> Result<Self, HelperError> {
        Ok(Self { proxy: Helper1Proxy::new(conn).await? })
    }

    /// Connects to the system bus.
    ///
    /// # Errors
    /// Fails when the system bus is unreachable.
    pub async fn system() -> Result<Self, HelperError> {
        Self::new(&zbus::Connection::system().await?).await
    }
}

impl Helper for DbusHelper {
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> Fut<'a, (AuthOutcome, String)> {
        Box::pin(async move {
            // A refusal to answer at all is never a wrong password.
            let asked = self.proxy.authenticate(user, password).await;
            let (ok, reason, admin, ticket) = asked.map_err(|e| HelperError::Unavailable(e.to_string()))?;
            Ok((AuthOutcome::from_wire(ok, &reason, admin), ticket))
        })
    }

    fn keep_alive<'a>(&'a self, ticket: &'a str) -> Fut<'a, ()> {
        Box::pin(async move { Ok(self.proxy.keep_alive(ticket).await?) })
    }

    fn sign_out<'a>(&'a self, ticket: &'a str) -> Fut<'a, ()> {
        Box::pin(async move { Ok(self.proxy.sign_out(ticket).await?) })
    }

    fn open_terminal<'a>(&'a self, ticket: &'a str, cols: u16, rows: u16) -> Fut<'a, (String, OwnedFd)> {
        Box::pin(async move {
            let (id, master) = self.proxy.open_terminal(ticket, cols, rows).await?;
            Ok((id, master.into()))
        })
    }

    fn open_files<'a>(&'a self, ticket: &'a str) -> Fut<'a, (String, OwnedFd)> {
        Box::pin(async move {
            let (id, socket) = self.proxy.open_files(ticket).await?;
            Ok((id, socket.into()))
        })
    }

    fn close_terminal<'a>(&'a self, ticket: &'a str, id: &'a str) -> Fut<'a, ()> {
        Box::pin(async move { Ok(self.proxy.close_terminal(ticket, id).await?) })
    }

    fn ask<'a>(&'a self, ticket: &'a str, action: Action, args: String) -> Fut<'a, String> {
        Box::pin(async move { Ok(self.proxy.ask(ticket, action.name(), &args).await?) })
    }
}
