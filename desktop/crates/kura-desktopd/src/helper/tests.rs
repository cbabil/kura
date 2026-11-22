use std::io::{Read, Write};
use std::sync::Arc;

use kura_desktop_core::actions::{Action, ContainerArgs, JournalArgs, LogsArgs};
use kura_desktop_core::containers::ContainerAction;
use kura_desktop_core::stats::fixture::Fixture;
use kura_helper::fakes::{CONTAINER, FakeDocker, FakeJournal, FakeMachine, FakeShell, FakeSystem};
use kura_helper::{Authenticator, Backends, HelperIface, OBJECT_PATH, Pam, PamVerdict, Service};

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
    dir.write("etc/shells", "/bin/sh\n");
    dir.write("etc/passwd", "anna:x:1000:1000::/:/bin/sh\nbob:x:1001:1001::/:/bin/sh\nold:x:1002:1002::/:/bin/sh\n");
    let auth = Arc::new(Authenticator::new(Box::new(FakePam), dir.root()));
    let backends = Backends {
        docker: Arc::<FakeDocker>::default(),
        journal: Arc::<FakeJournal>::default(),
        shells: Arc::<FakeShell>::default(),
        machine: Arc::<FakeMachine>::default(),
        system: Arc::<FakeSystem>::default(),
        apps: Arc::<kura_helper::fakes::FakeApps>::default(),
    };
    let service = Arc::new(Service::new(auth, dir.root(), backends));
    let (a, b) = std::os::unix::net::UnixStream::pair().unwrap();
    let server = zbus::connection::Builder::unix_stream(a)
        .server(zbus::Guid::generate())
        .p2p()
        .serve_at(OBJECT_PATH, HelperIface::new(service, None))
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
        let (outcome, ticket) = helper.authenticate(user, password).await.unwrap();
        assert_eq!((outcome, ticket.is_empty()), (want, !matches!(want, AuthOutcome::Ok { .. })), "{user}");
    }
}

#[tokio::test]
async fn every_action_reaches_the_helper_and_refusals_come_back_typed() {
    let (helper, _server, _dir) = peer().await;
    let anna = helper.authenticate("anna", "pw").await.unwrap().1;
    let bob = helper.authenticate("bob", "pw").await.unwrap().1;
    let journal = JournalArgs { lines: 5, unit: "ssh.service".into(), priority: 3, after: String::new() };
    let control = |id: &str| ContainerArgs { id: id.into(), action: ContainerAction::Stop };
    let logs = |id: &str| LogsArgs { id: id.into(), lines: 7 };

    let (id, master) = helper.open_terminal(&bob, 80, 24).await.unwrap();
    let mut master = std::os::unix::net::UnixStream::from(master);
    master.write_all(b"ok").unwrap();
    let mut back = [0u8; 2];
    master.read_exact(&mut back).unwrap();
    assert_eq!(&back, b"OK");
    assert_eq!(helper.close_terminal(&bob, &id).await, Ok(()));
    assert!(ask(&helper, &bob, Action::ListContainers, &()).await.unwrap().contains(CONTAINER));
    assert_eq!(ask(&helper, &anna, Action::ControlContainer, &control(CONTAINER)).await.as_deref(), Ok(""));
    assert!(ask(&helper, &anna, Action::ContainerLogs, &logs(CONTAINER)).await.unwrap().contains("last 7"));
    assert!(ask(&helper, &anna, Action::ReadJournal, &journal).await.unwrap().contains("--unit=ssh.service"));
    assert!(ask(&helper, &bob, Action::UpdateStatus, &()).await.unwrap().contains("0.6.2"));

    assert_eq!(helper.close_terminal(&bob, &id).await, Err(HelperError::NotFound));
    assert_eq!(ask(&helper, &bob, Action::ControlContainer, &control(CONTAINER)).await, Err(HelperError::Admin));
    assert_eq!(ask(&helper, &anna, Action::ControlContainer, &control("web")).await, Err(HelperError::Invalid));
    assert_eq!(ask(&helper, &anna, Action::ContainerLogs, &logs("bbbbbbbbbbbb")).await, Err(HelperError::NotFound));
    assert_eq!(ask(&helper, "forged", Action::ReadJournal, &journal).await, Err(HelperError::SignedOut));
    assert_eq!(ask(&helper, &anna, Action::Terminal, &()).await, Err(HelperError::Invalid), "not by name");
    assert_eq!(helper.open_terminal(&bob, 0, 24).await.unwrap_err(), HelperError::Invalid);
    assert_eq!(helper.keep_alive(&bob).await, Ok(()));
    assert_eq!(helper.sign_out(&bob).await, Ok(()));
    assert_eq!(ask(&helper, &bob, Action::ListContainers, &()).await, Err(HelperError::SignedOut));
    assert_eq!(helper.keep_alive(&bob).await, Err(HelperError::SignedOut));
}

/// A bus policy that denies the call is not "administrators only", and no
/// other error of the bus is one of the helper's refusals either.
#[test]
fn the_buses_own_errors_mean_unavailable() {
    for e in [
        zbus::Error::from(zbus::fdo::Error::AccessDenied("policy".into())),
        zbus::Error::from(zbus::fdo::Error::UnknownObject("gone".into())),
        zbus::Error::from(zbus::fdo::Error::InvalidArgs("signature".into())),
        zbus::Error::Failure("x".into()),
    ] {
        assert!(matches!(HelperError::from(e), HelperError::Unavailable(_)));
    }
}

#[tokio::test]
async fn a_closed_bus_is_an_error() {
    let (helper, server, _dir) = peer().await;
    server.close().await.unwrap();
    let err = helper.authenticate("anna", "pw").await.unwrap_err();
    assert!(err.to_string().contains("kura-helper unavailable"));
    assert!(matches!(ask(&helper, "t", Action::ListContainers, &()).await, Err(HelperError::Unavailable(_))));
}

#[tokio::test]
async fn dev_helper_mimics_the_mock_api() {
    let dev = DevHelper::default();
    let cases = [
        ("kura", DEV_PASSWORD, AuthOutcome::Ok { admin: true }),
        ("chris", DEV_PASSWORD, AuthOutcome::Ok { admin: true }),
        ("guest", DEV_PASSWORD, AuthOutcome::Ok { admin: false }),
        ("kura", "nope", AuthOutcome::Wrong),
        ("expired", DEV_PASSWORD, AuthOutcome::Expired),
        ("expired", "nope", AuthOutcome::Wrong),
        ("root", DEV_PASSWORD, AuthOutcome::Wrong),
        ("stranger", DEV_PASSWORD, AuthOutcome::Wrong),
    ];
    for (user, password, want) in cases {
        assert_eq!(dev.authenticate(user, password).await.unwrap().0, want, "{user}");
    }
    let ticket = dev.authenticate("kura", DEV_PASSWORD).await.unwrap().1;
    assert!(ask(&dev, &ticket, Action::ListContainers, &()).await.unwrap().contains("immich-server"));
    assert_eq!(dev.keep_alive(&ticket).await, Ok(()));
    assert_eq!(dev.sign_out(&ticket).await, Ok(()));
    assert_eq!(ask(&dev, &ticket, Action::ListContainers, &()).await, Err(HelperError::SignedOut));
    // the real rules, not a copy of them
    let guest = dev.authenticate("guest", DEV_PASSWORD).await.unwrap().1;
    let stop = ContainerArgs { id: "aaaaaaaaaaaa".into(), action: ContainerAction::Stop };
    assert_eq!(ask(&dev, &guest, Action::ControlContainer, &stop).await, Err(HelperError::Admin));
    assert_eq!(dev.open_terminal(&guest, 0, 24).await.unwrap_err(), HelperError::Invalid);
}
