//! The D-Bus object `/io/kura/Helper` with interface `io.kura.Helper`. Who may
//! call it is set by the bus policy (only `kura-desktop`).

use std::sync::Arc;

use zeroize::Zeroizing;

use crate::authenticate::Authenticator;

/// The helper's well-known name on the system bus.
pub const BUS_NAME: &str = "io.kura.Helper";
/// The helper's object path.
pub const OBJECT_PATH: &str = "/io/kura/Helper";

/// The served object.
pub struct HelperIface {
    auth: Arc<Authenticator>,
}

impl HelperIface {
    /// Serves `auth` over D-Bus.
    pub fn new(auth: Arc<Authenticator>) -> Self {
        Self { auth }
    }
}

#[zbus::interface(name = "io.kura.Helper")]
impl HelperIface {
    /// Checks a password: `(ok, reason, admin)`, where reason is "", "wrong"
    /// or "expired". The password is wiped from memory afterwards.
    async fn authenticate(&self, user: String, password: String) -> (bool, String, bool) {
        let password = Zeroizing::new(password);
        let auth = self.auth.clone();
        let user_for_log = user.clone();
        let outcome = tokio::task::spawn_blocking(move || auth.authenticate(&user, &password)).await;
        match outcome {
            Ok(o) => {
                tracing::info!(user = %user_for_log, ok = matches!(o, kura_desktop_core::auth::AuthOutcome::Ok { .. }), "authenticate");
                o.to_wire()
            }
            Err(e) => {
                tracing::error!("password check failed: {e}");
                kura_desktop_core::auth::AuthOutcome::Wrong.to_wire()
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::authenticate::tests::authenticator;

    #[zbus::proxy(interface = "io.kura.Helper", default_path = "/io/kura/Helper")]
    trait Helper {
        fn authenticate(&self, user: &str, password: &str) -> zbus::Result<(bool, String, bool)>;
    }

    #[tokio::test]
    async fn answers_over_a_peer_to_peer_bus() {
        let (auth, _dir) = authenticator();
        let (a, b) = std::os::unix::net::UnixStream::pair().unwrap();
        let guid = zbus::Guid::generate();
        let server = zbus::connection::Builder::unix_stream(a)
            .server(guid)
            .p2p()
            .serve_at(OBJECT_PATH, HelperIface::new(Arc::new(auth)))
            .build();
        let client = zbus::connection::Builder::unix_stream(b).p2p().build();
        let (server, client) = tokio::try_join!(server, client).unwrap();
        let proxy = HelperProxy::builder(&client).destination(BUS_NAME).build().await.unwrap();
        let cases = [
            ("anna", "kura", (true, "", true)),
            ("bob", "x", (false, "wrong", false)),
            ("old", "kura", (false, "expired", false)),
        ];
        for (user, password, (ok, reason, admin)) in cases {
            assert_eq!(proxy.authenticate(user, password).await.unwrap(), (ok, reason.to_owned(), admin), "{user}");
        }
        drop(server);
    }
}
