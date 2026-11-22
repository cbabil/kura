use std::io::{Read, Write};

use super::tests::rig;
use crate::refusal::Refusal;
use crate::terminal::MAX_PER_USER;

#[tokio::test]
async fn every_person_with_a_shell_gets_an_agent_of_their_own() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    let (id, socket) = rig.service.open_files(&bob).await.unwrap();
    assert_eq!(rig.shells.opened.lock().unwrap().as_slice(), ["bob-files-0"]);
    let mut socket = std::os::unix::net::UnixStream::from(socket);
    socket.write_all(b"ls").unwrap();
    let mut back = [0u8; 2];
    socket.read_exact(&mut back).unwrap();
    assert_eq!(&back, b"LS");

    assert_eq!(rig.service.open_files("forged").await.unwrap_err(), Refusal::SignedOut);
    // carl has no login shell: no terminal, and so no files either.
    let carl = rig.sign_in("carl").await;
    assert_eq!(rig.service.open_files(&carl).await.unwrap_err(), Refusal::NoShell);
    let anna = rig.sign_in("anna").await;
    assert_eq!(rig.service.close_terminal(&anna, &id).await, Err(Refusal::NotFound), "not anna's");
    assert_eq!(rig.service.close_terminal(&bob, &id).await, Ok(()));
    assert_eq!(rig.service.ask(&bob, "files", "").await, Err(Refusal::Invalid("action".into())), "not by name");
}

#[tokio::test]
async fn agents_that_ended_do_not_count_and_a_changed_password_stops_the_rest() {
    let rig = rig();
    let anna = rig.sign_in("anna").await;
    // Eight sign-ins of bob used Files and went idle: their agents ended.
    let mut tickets = Vec::new();
    for _ in 0..MAX_PER_USER {
        let ticket = rig.sign_in("bob").await;
        rig.service.open_files(&ticket).await.unwrap();
        tickets.push(ticket);
    }
    rig.shells.ended.store(true, std::sync::atomic::Ordering::Relaxed);
    let bob = rig.sign_in("bob").await;
    assert!(rig.service.open_files(&bob).await.is_ok(), "ended agents hold no place");
    rig.shells.ended.store(false, std::sync::atomic::Ordering::Relaxed);
    rig.service.open_terminal(&bob, 80, 24).await.unwrap();

    let closed = || rig.shells.closed.lock().unwrap().len();
    let before = closed();
    rig.service
        .ask(&anna, "change-setting", r#"{"what":"user-password","name":"bob","password":"by anna"}"#)
        .await
        .unwrap();
    assert_eq!(closed() - before, 2, "bob's agent and shell are stopped with his sign-ins");
    assert_eq!(rig.service.open_files(&bob).await.unwrap_err(), Refusal::SignedOut);
}

#[tokio::test]
async fn a_ticket_has_one_agent_which_ends_with_it() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    rig.service.open_files(&bob).await.unwrap();
    rig.service.open_files(&bob).await.unwrap();
    assert_eq!(rig.shells.closed.lock().unwrap().as_slice(), ["bob-files-0"], "the earlier one is stopped");
    // Agents do not take the places of terminals.
    for _ in 0..MAX_PER_USER {
        rig.service.open_terminal(&bob, 80, 24).await.unwrap();
    }
    rig.service.sign_out(&bob).await;
    let closed = rig.shells.closed.lock().unwrap().clone();
    assert_eq!(closed.len(), 2 + MAX_PER_USER);
    assert!(closed.contains(&"bob-files-1".to_owned()));
    assert_eq!(rig.service.open_files(&bob).await.unwrap_err(), Refusal::SignedOut);
}

#[tokio::test]
async fn an_agent_that_cannot_start_is_unavailable() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    rig.shells.fail.store(true, std::sync::atomic::Ordering::Relaxed);
    assert!(matches!(rig.service.open_files(&bob).await, Err(Refusal::Unavailable(_))));
}
