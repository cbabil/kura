use std::sync::atomic::Ordering;

use kura_desktop_core::containers::ContainerAction;

use super::tests::rig;
use crate::fakes::CONTAINER;
use crate::refusal::Refusal;

#[tokio::test]
async fn ask_does_the_named_action_and_nothing_else() {
    let rig = rig();
    let anna = rig.sign_in("anna").await;
    let ask = |action: &'static str, args: &'static str| rig.service.ask(&anna, action, args);
    assert!(ask("list-containers", "").await.unwrap().contains("\"web\""));
    assert_eq!(ask("control-container", r#"{"id":"aaaaaaaaaaaa","action":"restart"}"#).await.unwrap(), "");
    assert!(ask("container-logs", r#"{"id":"aaaaaaaaaaaa","lines":3}"#).await.unwrap().contains("last 3"));
    let journal = ask("read-journal", r#"{"lines":5,"unit":"ssh.service","priority":-1,"after":""}"#).await.unwrap();
    assert!(journal.contains("--unit=ssh.service"));
    assert_eq!(rig.docker.calls.lock().unwrap().as_slice(), [format!("restart {CONTAINER}")]);

    let invalid = [
        ("terminal", ""),
        ("format-disk", "{}"),
        ("", ""),
        ("control-container", "{}"),
        ("control-container", r#"{"id":"aaaaaaaaaaaa","action":"kill"}"#),
        ("list-containers", "{}"),
        ("update-status", r#"["x"]"#),
        ("control-container", r#"{"id":"aaaaaaaaaaaa","action":"restart","extra":1}"#),
        ("container-logs", r#"{"id":"aaaaaaaaaaaa","lines":"many"}"#),
        ("power", r#"{"how":"hibernate"}"#),
        ("start-update", r#"{"what":"install && reboot"}"#),
    ];
    for (action, args) in invalid {
        assert!(matches!(ask(action, args).await, Err(Refusal::Invalid(_))), "{action} {args}");
    }
    assert_eq!(rig.service.ask("forged", "list-containers", "").await, Err(Refusal::SignedOut));
    assert!(rig.machine.asked.lock().unwrap().is_empty(), "nothing invalid reached the machine");
}

#[tokio::test]
async fn everyone_sees_whether_an_update_waits_and_administrators_install_it() {
    let rig = rig();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    std::fs::create_dir_all(rig.dir.path().join("usr/lib/kura")).unwrap();
    std::fs::write(rig.dir.path().join("usr/lib/kura/release"), "BRAND_VERSION=\"0.6.1\"\n").unwrap();
    let status = rig.service.update_status(&bob).await.unwrap();
    assert_eq!(status, r#"{"current":"0.6.1","available":"0.6.2","restartRequired":false,"job":null}"#);

    assert_eq!(rig.service.ask(&bob, "start-update", r#"{"what":"install"}"#).await, Err(Refusal::Admin));
    assert_eq!(rig.service.ask(&anna, "start-update", r#"{"what":"install"}"#).await.unwrap(), "");
    assert_eq!(rig.machine.asked.lock().unwrap().as_slice(), ["install"]);
    assert_eq!(
        rig.service.ask(&anna, "start-update", r#"{"what":"check"}"#).await,
        Err(Refusal::Busy),
        "one at a time"
    );

    std::fs::create_dir_all(rig.dir.path().join("run")).unwrap();
    std::fs::write(rig.dir.path().join("run/reboot-required"), "").unwrap();
    let for_admin = rig.service.ask(&anna, "update-status", "").await.unwrap();
    assert!(for_admin.contains(r#""restartRequired":true"#) && for_admin.contains("Get:1 kura 0.6.2"), "{for_admin}");
    let read = rig.machine.outputs.load(Ordering::Relaxed);
    let for_bob = rig.service.update_status(&bob).await.unwrap();
    assert!(for_bob.contains(r#""job":{"state":"running","output":[]}"#), "no output for others: {for_bob}");
    assert_eq!(rig.machine.outputs.load(Ordering::Relaxed), read, "and it is not even read for them");

    // not while it installs: a restart would cut dpkg off half-way
    assert_eq!(rig.service.ask(&anna, "power", r#"{"how":"restart"}"#).await, Err(Refusal::Busy));
    assert_eq!(rig.machine.asked.lock().unwrap().as_slice(), ["install"]);
}

#[tokio::test]
async fn two_requests_start_one_update() {
    let rig = rig();
    let anna = rig.sign_in("anna").await;
    let ask = || rig.service.ask(&anna, "start-update", r#"{"what":"check"}"#);
    let (a, b) = tokio::join!(ask(), ask());
    assert_eq!([a.is_ok(), b.is_ok()].iter().filter(|ok| **ok).count(), 1);
    assert_eq!(rig.machine.asked.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn only_administrators_switch_the_machine_off() {
    let rig = rig();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    for how in ["restart", "shutdown"] {
        let args = format!(r#"{{"how":"{how}"}}"#);
        assert_eq!(rig.service.ask(&bob, "power", &args).await, Err(Refusal::Admin));
        assert_eq!(rig.service.ask(&anna, "power", &args).await.unwrap(), "");
    }
    assert_eq!(rig.machine.asked.lock().unwrap().as_slice(), ["restart", "shutdown"]);
    rig.machine.fail.store(true, Ordering::Relaxed);
    assert!(matches!(rig.service.ask(&anna, "power", r#"{"how":"restart"}"#).await, Err(Refusal::Unavailable(_))));
    assert!(matches!(
        rig.service.ask(&anna, "start-update", r#"{"what":"check"}"#).await,
        Err(Refusal::Unavailable(_))
    ));
}

#[tokio::test]
async fn containers_for_everyone_to_see_and_administrators_to_run() {
    let rig = rig();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    let list = rig.service.list_containers(&bob).await.unwrap();
    assert!(list.starts_with(r#"[{"id":"aaaaaaaaaaaa","name":"web""#), "{list}");
    assert_eq!(rig.service.container_action(&bob, CONTAINER, ContainerAction::Stop).await, Err(Refusal::Admin));
    assert_eq!(rig.service.container_logs(&bob, CONTAINER, 10).await, Err(Refusal::Admin));

    for action in [ContainerAction::Start, ContainerAction::Stop, ContainerAction::Restart] {
        assert_eq!(rig.service.container_action(&anna, CONTAINER, action).await, Ok(()));
    }
    assert_eq!(rig.docker.calls.lock().unwrap().len(), 3);
    let logs = rig.service.container_logs(&anna, CONTAINER, 10).await.unwrap();
    assert_eq!(logs, r#"[{"t":1,"stream":"stdout","text":"last 10"}]"#);

    for id in ["web", "../../etc", ""] {
        let refused = rig.service.container_action(&anna, id, ContainerAction::Stop).await;
        assert!(matches!(refused, Err(Refusal::Invalid(_))), "{id}");
    }
    assert_eq!(
        rig.service.container_action(&anna, "bbbbbbbbbbbb", ContainerAction::Stop).await,
        Err(Refusal::NotFound)
    );
    for (id, lines) in [("web", 10), (CONTAINER, 0), (CONTAINER, kura_desktop_core::containers::MAX_LOG_LINES + 1)] {
        assert!(matches!(rig.service.container_logs(&anna, id, lines).await, Err(Refusal::Invalid(_))), "{id} {lines}");
    }
    assert_eq!(rig.docker.calls.lock().unwrap().len(), 3, "nothing invalid reached Docker");

    rig.docker.down.store(true, Ordering::Relaxed);
    assert!(matches!(rig.service.list_containers(&anna).await, Err(Refusal::Unavailable(_))));
    assert!(matches!(
        rig.service.container_action(&anna, CONTAINER, ContainerAction::Stop).await,
        Err(Refusal::Unavailable(_))
    ));
}

#[tokio::test]
async fn the_journal_is_for_administrators() {
    let rig = rig();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    assert_eq!(rig.service.read_journal(&bob, 10, "", -1, "").await, Err(Refusal::Admin));
    let page = rig.service.read_journal(&anna, 10, "ssh.service", 3, "").await.unwrap();
    assert!(page.contains(r#""cursor":"s=1""#) && page.contains("--unit=ssh.service --priority=3"), "{page}");
    for (lines, unit, priority, after) in
        [(0, "", -1, ""), (10, "--root=/", -1, ""), (10, "", 9, ""), (10, "", -1, "-x")]
    {
        let got = rig.service.read_journal(&anna, lines, unit, priority, after).await;
        assert!(matches!(got, Err(Refusal::Invalid(_))), "{lines} {unit} {priority} {after}");
    }
    rig.journal.down.store(true, Ordering::Relaxed);
    assert!(matches!(rig.service.read_journal(&anna, 10, "", -1, "").await, Err(Refusal::Unavailable(_))));
}

/// Gives the fake root the Browser's command and programs (ADR-036).
fn with_browser(dir: &std::path::Path) {
    for file in kura_desktop_core::browser::files() {
        let path = dir.join(file.trim_start_matches('/'));
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, "").unwrap();
    }
}

#[tokio::test]
async fn each_person_opens_and_quits_their_own_browser() {
    use std::io::{Read, Write};
    let rig = rig();
    let (anna, bob, carl) = (rig.sign_in("anna").await, rig.sign_in("bob").await, rig.sign_in("carl").await);
    assert!(matches!(rig.service.open_browser(&bob).await, Err(Refusal::Unavailable(_))), "no packages");
    assert!(rig.browsers.calls.lock().unwrap().is_empty());

    with_browser(rig.dir.path());
    // the connection handed over is the browser's own: bytes go both ways
    let fd = rig.service.open_browser(&bob).await.expect("not an administrator, and still");
    let mut theirs = std::os::unix::net::UnixStream::from(fd);
    rig.browsers.servers.lock().unwrap()[0].write_all(b"RFB 003.008\n").unwrap();
    let mut greeting = [0u8; 12];
    theirs.read_exact(&mut greeting).unwrap();
    assert_eq!(&greeting, b"RFB 003.008\n");
    rig.service.open_browser(&anna).await.unwrap();
    assert_eq!(rig.service.open_browser(&carl).await.err(), Some(Refusal::NoShell), "an account without a login shell");
    assert_eq!(rig.service.ask(&bob, "browser-stop", "").await.unwrap(), "");
    assert_eq!(rig.browsers.calls.lock().unwrap().as_slice(), ["open bob", "open anna", "stop bob"], "each their own");

    // the browser is its own D-Bus method; its stop takes no arguments
    for (action, args) in [("browser", ""), ("browser-stop", r#"{"user":"anna"}"#)] {
        assert!(matches!(rig.service.ask(&bob, action, args).await, Err(Refusal::Invalid(_))), "{action} {args}");
    }
    assert_eq!(rig.service.open_browser("forged").await.err(), Some(Refusal::SignedOut));
    rig.browsers.fail.store(true, Ordering::Relaxed);
    assert!(matches!(rig.service.open_browser(&anna).await, Err(Refusal::Unavailable(_))));
}
