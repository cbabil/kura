use std::sync::Arc;

use kura_desktop_core::root::SysRoot;
use kura_helper::{Authenticator, HelperIface, OBJECT_PATH, Pam, PamVerdict};

use super::*;

struct FakePam;
impl Pam for FakePam {
    fn check(&self, user: &str, password: &str) -> PamVerdict {
        match (user, password) {
            ("old", "pw") => PamVerdict::Expired,
            (_, "pw") => PamVerdict::Ok,
            _ => PamVerdict::Wrong,
        }
    }
}

/// desktopd's client against kura-helper's real interface, over a socket pair.
async fn peer() -> (DbusHelper, zbus::Connection, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir(dir.path().join("etc")).unwrap();
    std::fs::write(dir.path().join("etc/group"), "sudo:x:27:anna\n").unwrap();
    let auth = Arc::new(Authenticator::new(Box::new(FakePam), SysRoot::new(dir.path())));
    let (a, b) = std::os::unix::net::UnixStream::pair().unwrap();
    let server = zbus::connection::Builder::unix_stream(a)
        .server(zbus::Guid::generate())
        .p2p()
        .serve_at(OBJECT_PATH, HelperIface::new(auth))
        .build();
    let client = zbus::connection::Builder::unix_stream(b).p2p().build();
    let (server, client) = tokio::try_join!(server, client).unwrap();
    (DbusHelper::new(client), server, dir)
}

#[tokio::test]
async fn dbus_client_reads_the_helpers_answers() {
    let (helper, _server, _dir) = peer().await;
    let cases = [
        ("anna", "pw", AuthOutcome::Ok { admin: true }),
        ("bob", "pw", AuthOutcome::Ok { admin: false }),
        ("bob", "nope", AuthOutcome::Wrong),
        ("old", "pw", AuthOutcome::Expired),
    ];
    for (user, password, want) in cases {
        assert_eq!(helper.authenticate(user, password).await.unwrap(), want, "{user}");
    }
}

#[tokio::test]
async fn a_closed_bus_is_an_error() {
    let (helper, server, _dir) = peer().await;
    server.close().await.unwrap();
    let err = helper.authenticate("anna", "pw").await.unwrap_err();
    assert!(err.to_string().contains("kura-helper unavailable"));
}

#[tokio::test]
async fn dev_helper_mimics_the_mock_api() {
    let cases = [
        ("kura", DEV_PASSWORD, AuthOutcome::Ok { admin: true }),
        ("kura", "nope", AuthOutcome::Wrong),
        ("expired", DEV_PASSWORD, AuthOutcome::Expired),
        ("expired", "nope", AuthOutcome::Wrong),
    ];
    for (user, password, want) in cases {
        assert_eq!(DevHelper.authenticate(user, password).await.unwrap(), want);
    }
}
