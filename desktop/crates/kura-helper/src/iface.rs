//! The D-Bus object `/io/kura/Helper` with interface `io.kura.Helper1` (the 1
//! versions the interface), owned as `io.kura.Helper`. The bus policy lets
//! only `kura-desktop` call it, and the helper checks the caller's uid again.

use std::sync::Arc;

use kura_desktop_core::auth::{AuthOutcome, valid_user_name};
use zbus::message::Header;
use zeroize::Zeroizing;

use crate::authenticate::Authenticator;

/// The helper's well-known name on the system bus.
pub const BUS_NAME: &str = "io.kura.Helper";
/// The helper's object path.
pub const OBJECT_PATH: &str = "/io/kura/Helper";

/// The served object.
pub struct HelperIface {
    auth: Arc<Authenticator>,
    /// The only uid allowed to call, checked with the bus on every call on
    /// top of the bus policy; `None` on a private peer-to-peer connection.
    caller: Option<u32>,
}

impl HelperIface {
    /// Serves `auth` over D-Bus to callers running as `caller`.
    pub fn new(auth: Arc<Authenticator>, caller: Option<u32>) -> Self {
        Self { auth, caller }
    }

    /// True when the message's sender runs as the allowed uid.
    async fn caller_allowed(&self, conn: &zbus::Connection, hdr: &Header<'_>) -> bool {
        let Some(allowed) = self.caller else { return true };
        let uid = async {
            let sender = hdr.sender().ok_or(zbus::Error::MissingField)?.to_owned();
            let bus = zbus::fdo::DBusProxy::new(conn).await?;
            Ok::<u32, zbus::Error>(bus.get_connection_unix_user(sender.into()).await?)
        };
        match uid.await {
            Ok(uid) if uid == allowed => true,
            other => {
                tracing::warn!("refused Authenticate from {other:?}");
                false
            }
        }
    }
}

#[zbus::interface(name = "io.kura.Helper1")]
impl HelperIface {
    /// Checks a password: `(ok, reason, admin)`, where reason is "", "wrong"
    /// or "expired". The password is wiped from memory afterwards.
    async fn authenticate(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
        user: String,
        password: String,
    ) -> zbus::fdo::Result<(bool, String, bool)> {
        let password = Zeroizing::new(password);
        if !self.caller_allowed(conn, &hdr).await {
            return Err(zbus::fdo::Error::AccessDenied("only kura-desktopd may call this".into()));
        }
        let auth = self.auth.clone();
        let check = move || {
            let outcome = auth.authenticate(&user, &password);
            let shown = if valid_user_name(&user) { user.as_str() } else { "(invalid)" };
            tracing::info!(user = shown, ok = matches!(outcome, AuthOutcome::Ok { .. }), "authenticate");
            outcome
        };
        let outcome = tokio::task::spawn_blocking(check).await.unwrap_or_else(|e| {
            tracing::error!("password check failed: {e}");
            AuthOutcome::Wrong
        });
        Ok(outcome.to_wire())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::authenticate::tests::authenticator;

    #[zbus::proxy(interface = "io.kura.Helper1", default_path = "/io/kura/Helper")]
    trait Helper {
        fn authenticate(&self, user: &str, password: &str) -> zbus::Result<(bool, String, bool)>;
    }

    /// A helper and a client over a socket pair; `caller` as in production.
    async fn peer(caller: Option<u32>) -> (HelperProxy<'static>, zbus::Connection, tempfile::TempDir) {
        let (auth, dir) = authenticator();
        let (a, b) = std::os::unix::net::UnixStream::pair().unwrap();
        let server = zbus::connection::Builder::unix_stream(a)
            .server(zbus::Guid::generate())
            .p2p()
            .serve_at(OBJECT_PATH, HelperIface::new(Arc::new(auth), caller))
            .build();
        let client = zbus::connection::Builder::unix_stream(b).p2p().build();
        let (server, client) = tokio::try_join!(server, client).unwrap();
        let proxy = HelperProxy::builder(&client).destination(BUS_NAME).build().await.unwrap();
        (proxy, server, dir)
    }

    #[tokio::test]
    async fn answers_over_a_peer_to_peer_bus() {
        let (proxy, _server, _dir) = peer(None).await;
        let cases = [
            ("anna", "kura", (true, "", true)),
            ("bob", "x", (false, "wrong", false)),
            ("old", "kura", (false, "expired", false)),
        ];
        for (user, password, (ok, reason, admin)) in cases {
            assert_eq!(proxy.authenticate(user, password).await.unwrap(), (ok, reason.to_owned(), admin), "{user}");
        }
    }

    /// Without a bus to vouch for the caller, a helper limited to one uid
    /// refuses.
    #[tokio::test]
    async fn refuses_a_caller_it_cannot_verify() {
        let (proxy, _server, _dir) = peer(Some(990)).await;
        let err = proxy.authenticate("anna", "kura").await.unwrap_err();
        assert!(err.to_string().contains("AccessDenied"), "{err}");
    }
}
