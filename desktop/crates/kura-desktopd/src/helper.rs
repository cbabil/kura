//! Password checks, delegated to `kura-helper` over the system D-Bus. A fake
//! stands in for development on a Mac (`dev-auth` feature) and in tests.

use std::future::Future;
use std::pin::Pin;

use kura_desktop_core::auth::AuthOutcome;

/// The boxed future an [`AuthHelper`] returns.
pub type AuthFuture<'a> = Pin<Box<dyn Future<Output = Result<AuthOutcome, HelperError>> + Send + 'a>>;

/// Checks a user name and password.
pub trait AuthHelper: Send + Sync {
    /// Asks whether `password` is right for `user`.
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> AuthFuture<'a>;
}

/// The helper could not be asked.
#[derive(Debug, thiserror::Error)]
#[error("kura-helper unavailable: {0}")]
pub struct HelperError(#[from] pub zbus::Error);

#[zbus::proxy(interface = "io.kura.Helper", default_service = "io.kura.Helper", default_path = "/io/kura/Helper")]
trait Helper {
    fn authenticate(&self, user: &str, password: &str) -> zbus::Result<(bool, String, bool)>;
}

/// `kura-helper` over a D-Bus connection.
pub struct DbusHelper {
    conn: zbus::Connection,
}

impl DbusHelper {
    /// Uses an open connection (the system bus, or a peer in tests).
    pub fn new(conn: zbus::Connection) -> Self {
        Self { conn }
    }

    /// Connects to the system bus.
    ///
    /// # Errors
    /// Fails when the system bus is unreachable.
    pub async fn system() -> Result<Self, HelperError> {
        Ok(Self::new(zbus::Connection::system().await?))
    }

    async fn call(&self, user: &str, password: &str) -> Result<AuthOutcome, HelperError> {
        let proxy = HelperProxy::builder(&self.conn).cache_properties(zbus::proxy::CacheProperties::No).build().await?;
        let (ok, reason, admin) = proxy.authenticate(user, password).await?;
        Ok(AuthOutcome::from_wire(ok, &reason, admin))
    }
}

impl AuthHelper for DbusHelper {
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> AuthFuture<'a> {
        Box::pin(self.call(user, password))
    }
}

/// The development password for [`DevHelper`].
pub const DEV_PASSWORD: &str = "kura";

/// A fake check: any valid user name with [`DEV_PASSWORD`] signs in as an
/// administrator, and the user "expired" gets the expired-password refusal
/// (like the interface's mock API).
#[derive(Debug, Default)]
pub struct DevHelper;

impl AuthHelper for DevHelper {
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> AuthFuture<'a> {
        let outcome = match (user, password == DEV_PASSWORD) {
            (_, false) => AuthOutcome::Wrong,
            ("expired", true) => AuthOutcome::Expired,
            _ => AuthOutcome::Ok { admin: true },
        };
        Box::pin(async move { Ok(outcome) })
    }
}

#[cfg(test)]
mod tests;
