use std::io::{Read, Write};
use std::sync::atomic::Ordering;

use kura_desktop_core::containers::ContainerAction;

use super::*;
use crate::authenticate::tests::{FakePam, root};
use crate::fakes::{CONTAINER, FakeApps, FakeBrowsers, FakeDocker, FakeJournal, FakeMachine, FakeShell, FakeSystem};
use crate::terminal::MAX_PER_USER;

pub(crate) struct Rig {
    pub service: Arc<Service>,
    pub docker: Arc<FakeDocker>,
    pub journal: Arc<FakeJournal>,
    pub shells: Arc<FakeShell>,
    pub machine: Arc<FakeMachine>,
    pub system: Arc<FakeSystem>,
    pub apps: Arc<FakeApps>,
    pub browsers: Arc<FakeBrowsers>,
    pub dir: tempfile::TempDir,
}

pub(crate) fn rig() -> Rig {
    let (root, dir) = root();
    let (docker, journal) = (Arc::<FakeDocker>::default(), Arc::<FakeJournal>::default());
    let (shells, machine, system) =
        (Arc::<FakeShell>::default(), Arc::<FakeMachine>::default(), Arc::<FakeSystem>::default());
    let (apps, browsers) = (Arc::<FakeApps>::default(), Arc::<FakeBrowsers>::default());
    let backends = Backends {
        docker: docker.clone(),
        journal: journal.clone(),
        shells: shells.clone(),
        machine: machine.clone(),
        system: system.clone(),
        apps: apps.clone(),
        browsers: browsers.clone(),
    };

    let auth = Arc::new(Authenticator::new(Box::new(FakePam), root.clone()));
    Rig {
        service: Arc::new(Service::new(auth, root, backends)),
        docker,
        journal,
        shells,
        machine,
        system,
        apps,
        browsers,
        dir,
    }
}

impl Rig {
    pub async fn sign_in(&self, user: &str) -> String {
        let (outcome, ticket) = self.service.authenticate(user.into(), Zeroizing::new("kura".into())).await;
        assert!(matches!(outcome, AuthOutcome::Ok { .. }), "{user}");
        ticket
    }
}

#[tokio::test]
async fn only_a_right_password_gives_a_ticket() {
    let rig = rig();
    let ticket = rig.sign_in("bob").await;
    assert_eq!(ticket.len(), 64);
    assert!(rig.service.list_containers(&ticket).await.is_ok());
    for (user, password) in [("bob", "nope"), ("old", "kura"), ("root", "kura"), ("Bad Name", "kura")] {
        let (outcome, ticket) = rig.service.authenticate(user.into(), Zeroizing::new(password.into())).await;
        assert!(!matches!(outcome, AuthOutcome::Ok { .. }) && ticket.is_empty(), "{user}");
    }
    assert_eq!(rig.service.list_containers("").await, Err(Refusal::SignedOut));
}

#[tokio::test]
async fn wrong_passwords_are_counted_here_too() {
    let rig = rig();
    for _ in 0..kura_desktop_core::ratelimit::MAX_FAILURES {
        let (outcome, _) = rig.service.authenticate("anna".into(), Zeroizing::new("nope".into())).await;
        assert_eq!(outcome, AuthOutcome::Wrong);
    }
    let (outcome, ticket) = rig.service.authenticate("anna".into(), Zeroizing::new("kura".into())).await;
    assert!(outcome == AuthOutcome::Wrong && ticket.is_empty(), "the right password is not even checked now");
    rig.sign_in("bob").await;
    for _ in 0..20 {
        rig.sign_in("bob").await;
        rig.service.authenticate("old".into(), Zeroizing::new("kura".into())).await;
    }
    assert!(rig.service.keep_alive(&rig.sign_in("bob").await).is_ok(), "right and expired passwords do not count");
    assert_eq!(rig.service.keep_alive("forged"), Err(Refusal::SignedOut));
}

#[tokio::test]
async fn a_flood_of_requests_is_refused_as_busy() {
    let rig = rig();
    let anna = rig.sign_in("anna").await;
    let held: Vec<_> = (0..SLOTS).map(|_| rig.service.slot().unwrap()).collect();
    assert_eq!(rig.service.list_containers(&anna).await, Err(Refusal::Busy));
    assert_eq!(rig.service.container_action(&anna, CONTAINER, ContainerAction::Stop).await, Err(Refusal::Busy));
    assert_eq!(rig.service.container_logs(&anna, CONTAINER, 5).await, Err(Refusal::Busy));
    assert_eq!(rig.service.read_journal(&anna, 5, "", -1, "").await, Err(Refusal::Busy));
    drop(held);
    assert!(rig.service.list_containers(&anna).await.is_ok());
}

#[tokio::test]
async fn a_shell_started_for_a_ticket_that_signed_out_meanwhile_is_stopped() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    let (opened, ()) = tokio::join!(rig.service.open_terminal(&bob, 80, 24), rig.service.sign_out(&bob));
    assert_eq!(opened.unwrap_err(), Refusal::SignedOut);
    assert_eq!(rig.shells.closed.lock().unwrap().as_slice(), ["bob-80x24-0"]);
}

#[tokio::test]
async fn parallel_requests_cannot_pass_the_users_limit() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    let all = (0..MAX_PER_USER + 4).map(|_| rig.service.open_terminal(&bob, 80, 24));
    let opened = futures_util::future::join_all(all).await;
    assert_eq!(opened.iter().filter(|o| o.is_ok()).count(), MAX_PER_USER);
    assert!(opened.iter().filter_map(|o| o.as_ref().err()).all(|e| *e == Refusal::Busy));
}

#[tokio::test]
async fn a_terminal_is_the_users_own_shell() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    let (id, master) = rig.service.open_terminal(&bob, 120, 40).await.unwrap();
    assert_eq!(rig.shells.opened.lock().unwrap().as_slice(), ["bob-120x40-0"]);
    let mut master = std::os::unix::net::UnixStream::from(master);
    master.write_all(b"id\n").unwrap();
    let mut back = [0u8; 3];
    master.read_exact(&mut back).unwrap();
    assert_eq!(&back, b"ID\n");

    let anna = rig.sign_in("anna").await;
    assert_eq!(rig.service.close_terminal(&anna, &id).await, Err(Refusal::NotFound), "not anna's");
    assert_eq!(rig.service.close_terminal(&bob, "nope").await, Err(Refusal::NotFound));
    assert_eq!(rig.service.close_terminal(&bob, &id).await, Ok(()));
    assert_eq!(rig.service.close_terminal(&bob, &id).await, Err(Refusal::NotFound), "already closed");
    assert_eq!(rig.shells.closed.lock().unwrap().as_slice(), ["bob-120x40-0"]);
}

#[tokio::test]
async fn terminals_are_refused_when_they_should_be() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    for (cols, rows) in [(0, 24), (80, 0), (501, 24), (80, 501)] {
        assert!(matches!(rig.service.open_terminal(&bob, cols, rows).await, Err(Refusal::Invalid(_))), "{cols}x{rows}");
    }
    let carl = rig.sign_in("carl").await;
    assert_eq!(rig.service.open_terminal(&carl, 80, 24).await.unwrap_err(), Refusal::NoShell);
    assert_eq!(rig.service.open_terminal("forged", 80, 24).await.unwrap_err(), Refusal::SignedOut);
    rig.shells.fail.store(true, Ordering::Relaxed);
    assert!(matches!(rig.service.open_terminal(&bob, 80, 24).await, Err(Refusal::Unavailable(_))));
    assert!(rig.shells.opened.lock().unwrap().is_empty());
}

#[tokio::test]
async fn terminals_are_counted_per_user_and_end_with_the_ticket() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    for _ in 0..MAX_PER_USER {
        rig.service.open_terminal(&bob, 80, 24).await.unwrap();
    }
    assert_eq!(rig.service.open_terminal(&bob, 80, 24).await.unwrap_err(), Refusal::Busy);
    let anna = rig.sign_in("anna").await;
    assert!(rig.service.open_terminal(&anna, 80, 24).await.is_ok(), "anna has her own count");

    // shells that ended on their own no longer count
    rig.shells.ended.store(true, Ordering::Relaxed);
    assert!(rig.service.open_terminal(&bob, 80, 24).await.is_ok());
    rig.shells.ended.store(false, Ordering::Relaxed);

    rig.service.sign_out(&bob).await;
    assert_eq!(rig.shells.closed.lock().unwrap().as_slice(), [format!("bob-80x24-{}", MAX_PER_USER + 1)]);
    assert_eq!(rig.service.open_terminal(&bob, 80, 24).await.unwrap_err(), Refusal::SignedOut);
    rig.service.sign_out("unknown").await;
}
