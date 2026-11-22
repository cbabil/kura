use std::io::{Read, Write};

use super::*;
use crate::service::tests::{Rig, rig};

#[zbus::proxy(interface = "io.kura.Helper1", default_path = "/io/kura/Helper")]
trait Helper {
    fn authenticate(&self, user: &str, password: &str) -> zbus::Result<(bool, String, bool, String)>;
    fn sign_out(&self, ticket: &str) -> zbus::Result<()>;
    fn keep_alive(&self, ticket: &str) -> zbus::Result<()>;
    fn open_terminal(&self, ticket: &str, cols: u16, rows: u16) -> zbus::Result<(String, OwnedFd)>;
    fn close_terminal(&self, ticket: &str, id: &str) -> zbus::Result<()>;
    fn ask(&self, ticket: &str, action: &str, args: &str) -> zbus::Result<String>;
}

/// A helper and a client over a socket pair; `caller` as in production.
async fn peer(caller: Option<u32>) -> (HelperProxy<'static>, zbus::Connection, Rig) {
    let rig = rig();
    let (a, b) = std::os::unix::net::UnixStream::pair().unwrap();
    let server = zbus::connection::Builder::unix_stream(a)
        .server(zbus::Guid::generate())
        .p2p()
        .serve_at(OBJECT_PATH, HelperIface::new(rig.service.clone(), caller))
        .build();
    let client = zbus::connection::Builder::unix_stream(b).p2p().build();
    let (server, client) = tokio::try_join!(server, client).unwrap();
    let proxy = HelperProxy::builder(&client).destination(BUS_NAME).build().await.unwrap();
    (proxy, server, rig)
}

#[tokio::test]
async fn answers_sign_ins_over_a_peer_to_peer_bus() {
    let (proxy, _server, _rig) = peer(None).await;
    let cases = [
        ("anna", "kura", (true, "", true)),
        ("bob", "x", (false, "wrong", false)),
        ("old", "kura", (false, "expired", false)),
    ];
    for (user, password, (ok, reason, admin)) in cases {
        let (got_ok, got_reason, got_admin, ticket) = proxy.authenticate(user, password).await.unwrap();
        assert_eq!((got_ok, got_reason.as_str(), got_admin), (ok, reason, admin), "{user}");
        assert_eq!(ticket.is_empty(), !ok, "{user}");
    }
}

#[tokio::test]
async fn every_action_works_over_the_bus_and_refusals_are_dbus_errors() {
    let (proxy, _server, rig) = peer(None).await;
    let anna = proxy.authenticate("anna", "kura").await.unwrap().3;
    let bob = proxy.authenticate("bob", "kura").await.unwrap().3;

    let (id, master) = proxy.open_terminal(&bob, 80, 24).await.unwrap();
    let mut master = std::os::unix::net::UnixStream::from(std::os::fd::OwnedFd::from(master));
    master.write_all(b"ls").unwrap();
    let mut back = [0u8; 2];
    master.read_exact(&mut back).unwrap();
    assert_eq!(&back, b"LS", "the file descriptor crossed the bus");
    proxy.close_terminal(&bob, &id).await.unwrap();

    let stop = r#"{"id":"aaaaaaaaaaaa","action":"stop"}"#;
    assert!(proxy.ask(&bob, "list-containers", "").await.unwrap().contains("\"web\""));
    assert_eq!(proxy.ask(&anna, "control-container", stop).await.unwrap(), "");
    assert!(proxy.ask(&anna, "update-status", "").await.unwrap().contains(r#""available":"0.6.2""#));

    let name = |e: zbus::Error| e.to_string();
    assert!(name(proxy.ask(&bob, "control-container", stop).await.unwrap_err()).contains("Error.Admin"));
    assert!(name(proxy.ask("forged", "list-containers", "").await.unwrap_err()).contains("Error.SignedOut"));
    assert!(name(proxy.ask(&anna, "container-logs", "{}").await.unwrap_err()).contains("Error.Invalid"));
    assert!(name(proxy.close_terminal(&bob, &id).await.unwrap_err()).contains("Error.NotFound"));
    proxy.keep_alive(&bob).await.unwrap();

    proxy.sign_out(&bob).await.unwrap();
    assert!(name(proxy.ask(&bob, "list-containers", "").await.unwrap_err()).contains("Error.SignedOut"));
    assert!(name(proxy.keep_alive(&bob).await.unwrap_err()).contains("Error.SignedOut"));
    assert_eq!(rig.docker.calls.lock().unwrap().as_slice(), ["stop aaaaaaaaaaaa"]);
}

/// Without a bus to vouch for the caller, a helper limited to one uid
/// refuses every method.
#[tokio::test]
async fn refuses_a_caller_it_cannot_verify() {
    let (proxy, _server, rig) = peer(Some(990)).await;
    let ticket = rig.sign_in("anna").await;
    let denied = |r: zbus::Result<()>| assert!(r.unwrap_err().to_string().contains("Error.Caller"));
    denied(proxy.authenticate("anna", "kura").await.map(|_| ()));
    denied(proxy.keep_alive(&ticket).await);
    denied(proxy.sign_out(&ticket).await);
    denied(proxy.open_terminal(&ticket, 80, 24).await.map(|_| ()));
    denied(proxy.close_terminal(&ticket, "x").await);
    denied(proxy.ask(&ticket, "list-containers", "").await.map(|_| ()));
    denied(proxy.ask(&ticket, "power", r#"{"how":"shutdown"}"#).await.map(|_| ()));
    assert!(rig.machine.asked.lock().unwrap().is_empty());
    assert!(rig.service.ask(&ticket, "list-containers", "").await.is_ok(), "the ticket itself is fine");
}
