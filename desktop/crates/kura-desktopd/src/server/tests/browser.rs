//! The Browser's WebSocket (ADR-036) against a stand-in VNC server on a
//! unix socket of the test's own.

use std::path::PathBuf;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_tungstenite::tungstenite::Message;

use super::ws::{Socket, connect_to, serve};
use super::*;

const PATH: &str = "/api/browser";

/// An app whose Browser listens at a socket in a folder of the test's.
fn app(viewers: usize) -> (TestApp, PathBuf, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let socket = dir.path().join("vnc.sock");
    let at = socket.clone();
    let app = TestApp::with(move |s| {
        s.fallback_uid = Some(1001);
        s.browser_socket = at;
        s.browser_wait = Duration::from_millis(300);
        s.browser_slots = Arc::new(tokio::sync::Semaphore::new(viewers));
    });
    (app, socket, dir)
}

/// A VNC server that greets each viewer as RFB does, then echoes.
fn vnc(socket: &std::path::Path) -> tokio::net::UnixListener {
    tokio::net::UnixListener::bind(socket).unwrap()
}

async fn echo(listener: tokio::net::UnixListener) {
    while let Ok((mut stream, _)) = listener.accept().await {
        tokio::spawn(async move {
            stream.write_all(b"RFB 003.008\n").await.unwrap();
            let mut buf = [0u8; 1024];
            while let Ok(n @ 1..) = stream.read(&mut buf).await {
                if stream.write_all(&buf[..n]).await.is_err() {
                    return;
                }
            }
        });
    }
}

async fn open(addr: SocketAddr, cookie: &str) -> Result<Socket, u16> {
    connect_to(addr, PATH, Some(&format!("https://{addr}")), Some(cookie)).await
}

/// The next binary message, within 5 s.
async fn next_bytes(socket: &mut Socket) -> Option<Vec<u8>> {
    let read = async {
        while let Some(Ok(msg)) = socket.next().await {
            match msg {
                Message::Binary(bytes) => return Some(bytes.to_vec()),
                Message::Close(_) => return None,
                _ => {}
            }
        }
        None
    };
    tokio::time::timeout(Duration::from_secs(5), read).await.ok().flatten()
}

#[tokio::test]
async fn the_upgrade_needs_this_origin_and_a_session() {
    let (app, socket, _dir) = app(4);
    tokio::spawn(echo(vnc(&socket)));
    let addr = serve(&app).await;
    let cookie = app.sign_in("guest").await;
    assert_eq!(connect_to(addr, PATH, None, Some(&cookie)).await.unwrap_err(), 403, "missing Origin");
    assert_eq!(connect_to(addr, PATH, Some("https://evil.example"), Some(&cookie)).await.unwrap_err(), 403);
    assert_eq!(connect_to(addr, PATH, Some(&format!("https://{addr}")), None).await.unwrap_err(), 401);
    assert!(open(addr, &cookie).await.is_ok(), "anyone signed in, administrator or not");
}

#[tokio::test]
async fn bytes_go_both_ways_unchanged() {
    let (app, socket, _dir) = app(4);
    tokio::spawn(echo(vnc(&socket)));
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let mut ws = open(addr, &cookie).await.unwrap();
    assert_eq!(next_bytes(&mut ws).await.unwrap(), b"RFB 003.008\n");
    let raw: Vec<u8> = (0..=255).collect();
    ws.send(Message::Binary(raw.clone().into())).await.unwrap();
    let mut back = Vec::new();
    while back.len() < raw.len() {
        back.extend(next_bytes(&mut ws).await.unwrap());
    }
    assert_eq!(back, raw);
    // text frames mean nothing to VNC and are dropped
    ws.send(Message::Text("hello".into())).await.unwrap();
    ws.send(Message::Binary(b"!".to_vec().into())).await.unwrap();
    assert_eq!(next_bytes(&mut ws).await.unwrap(), b"!");
}

#[tokio::test]
async fn a_browser_that_never_listens_is_unavailable() {
    let (app, _socket, _dir) = app(4);
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    assert_eq!(open(addr, &cookie).await.unwrap_err(), 503);
}

#[tokio::test]
async fn viewers_are_capped() {
    let (app, socket, _dir) = app(1);
    tokio::spawn(echo(vnc(&socket)));
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let mut first = open(addr, &cookie).await.unwrap();
    assert_eq!(open(addr, &cookie).await.unwrap_err(), 429);
    first.close(None).await.unwrap();
    // the slot comes back once the first viewer is gone
    let again = async {
        loop {
            match open(addr, &cookie).await {
                Ok(_) => return,
                Err(_) => tokio::time::sleep(Duration::from_millis(50)).await,
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(5), again).await.unwrap();
}

#[tokio::test]
async fn the_browser_quitting_or_a_sign_out_ends_the_view() {
    let (app, socket, _dir) = app(4);
    let listener = vnc(&socket);
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    // a server that greets and then quits: the view ends with it
    let quit = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        stream.write_all(b"RFB 003.008\n").await.unwrap();
        drop(stream);
        listener
    });
    let mut ws = open(addr, &cookie).await.unwrap();
    assert_eq!(next_bytes(&mut ws).await.unwrap(), b"RFB 003.008\n");
    assert_eq!(next_bytes(&mut ws).await, None, "closed when the browser quit");

    tokio::spawn(echo(quit.await.unwrap()));
    let mut ws = open(addr, &cookie).await.unwrap();
    assert!(next_bytes(&mut ws).await.is_some());
    app.send(request("POST", "/api/logout", Some(&cookie), None)).await;
    let ended = async {
        while let Some(Ok(msg)) = ws.next().await {
            if matches!(msg, Message::Close(_)) {
                break;
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(10), ended).await.expect("a sign-out ends the view");
}

#[tokio::test]
async fn system_info_says_whether_the_browser_is_there() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let (code, info) = status(&app, request("GET", "/api/system", Some(&cookie), None)).await;
    assert_eq!((code, &info["browser"]), (200, &serde_json::Value::Bool(false)));
}

#[tokio::test]
async fn anyone_signed_in_quits_the_shared_browser() {
    let app = TestApp::with_guests();
    let cookie = app.sign_in("guest").await;
    let (code, _) = status(&app, request("POST", "/api/browser/stop", Some(&cookie), None)).await;
    assert_eq!(code, 204);
    let (code, _) = status(&app, request("POST", "/api/browser/stop", None, None)).await;
    assert_eq!(code, 401);
    // like every change, it needs the interface's header
    let forged = Request::builder()
        .method("POST")
        .uri("/api/browser/stop")
        .header(header::HOST, HOST)
        .header(header::COOKIE, &cookie)
        .body(Body::empty())
        .unwrap();
    assert_eq!(app.send(forged).await.0.status(), 403);
}
