use std::sync::Arc;

use kura_desktop_core::stats::fixture::Fixture;
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
async fn peer() -> (DbusHelper, zbus::Connection, Fixture) {
    let dir = Fixture::full();
    dir.write("etc/group", "sudo:x:27:anna\n");
    dir.write("etc/passwd", "anna:x:1000:1000::/:/bin/sh\nbob:x:1001:1001::/:/bin/sh\nold:x:1002:1002::/:/bin/sh\n");
    let auth = Arc::new(Authenticator::new(Box::new(FakePam), dir.root()));
    let (a, b) = std::os::unix::net::UnixStream::pair().unwrap();
    let server = zbus::connection::Builder::unix_stream(a)
        .server(zbus::Guid::generate())
        .p2p()
        .serve_at(OBJECT_PATH, HelperIface::new(auth, None))
        .build();
    let client = zbus::connection::Builder::unix_stream(b).p2p().build();
    let (server, client) = tokio::try_join!(server, client).unwrap();
    (DbusHelper::new(&client).await.unwrap(), server, dir)
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
