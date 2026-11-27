//! The Browser's WebSocket (ADR-036) against the development helper, whose
//! browsers are stand-in VNC servers that greet and then echo.

use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message;

use super::ws::{Socket, connect_to, serve};
use super::*;

const PATH: &str = "/api/browser";

/// An app where people without a fixture account can sign in, with at most
/// `views` browser views. Its helper's browsers greet as RFB does, then echo.
fn app(views: usize) -> TestApp {
    TestApp::with(move |s| {
        s.fallback_uid = Some(1001);
        s.browser_slots = Arc::new(tokio::sync::Semaphore::new(views));
    })
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

/// Waits until the socket closes; false when it stays open 10 s.
async fn closes(ws: &mut Socket) -> bool {
    let ended = async {
        while let Some(Ok(msg)) = ws.next().await {
            if matches!(msg, Message::Close(_)) {
                break;
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(10), ended).await.is_ok()
}

#[tokio::test]
async fn the_upgrade_needs_this_origin_a_session_and_a_login_shell() {
    let app = app(4);
    let addr = serve(&app).await;
    let cookie = app.sign_in("guest").await;
    assert_eq!(connect_to(addr, PATH, None, Some(&cookie)).await.unwrap_err(), 403, "missing Origin");
    assert_eq!(connect_to(addr, PATH, Some("https://evil.example"), Some(&cookie)).await.unwrap_err(), 403);
    assert_eq!(connect_to(addr, PATH, Some(&format!("https://{addr}")), None).await.unwrap_err(), 401);
    let noshell = app.sign_in("noshell").await;
    assert_eq!(open(addr, &noshell).await.unwrap_err(), 403, "no login shell, no browser");
    assert!(open(addr, &cookie).await.is_ok(), "anyone with a login shell, administrator or not");
}

#[tokio::test]
async fn bytes_go_both_ways_unchanged() {
    let app = app(4);
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
async fn a_browser_that_does_not_start_is_unavailable() {
    let app = app(4);
    app.helper.1.store(true, std::sync::atomic::Ordering::Relaxed);
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    assert_eq!(open(addr, &cookie).await.unwrap_err(), 503);
}

#[tokio::test]
async fn views_are_capped() {
    let app = app(1);
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let mut first = open(addr, &cookie).await.unwrap();
    assert_eq!(open(addr, &cookie).await.unwrap_err(), 429);
    first.close(None).await.unwrap();
    // the slot comes back once the first view is gone
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
async fn quitting_ends_only_ones_own_browser_and_a_sign_out_ends_the_view() {
    let app = app(4);
    let addr = serve(&app).await;
    let (kura, chris) = (app.sign_in("kura").await, app.sign_in("chris").await);
    let (mut mine, mut theirs) = (open(addr, &kura).await.unwrap(), open(addr, &chris).await.unwrap());
    assert!(next_bytes(&mut mine).await.is_some() && next_bytes(&mut theirs).await.is_some());
    let (code, _) = status(&app, request("POST", "/api/browser/stop", Some(&kura), None)).await;
    assert_eq!(code, 204);
    assert!(closes(&mut mine).await, "kura's browser quit, and its view with it");
    theirs.send(Message::Binary(b"still here".to_vec().into())).await.unwrap();
    assert_eq!(next_bytes(&mut theirs).await.unwrap(), b"still here", "chris's browser is chris's own");
    app.send(request("POST", "/api/logout", Some(&chris), None)).await;
    assert!(closes(&mut theirs).await, "a sign-out ends the view");
}

#[tokio::test]
async fn system_info_says_whether_the_browser_is_there() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let (code, info) = status(&app, request("GET", "/api/system", Some(&cookie), None)).await;
    assert_eq!((code, &info["browser"]), (200, &serde_json::Value::Bool(false)));
}

#[tokio::test]
async fn quitting_needs_a_session_and_the_interfaces_header() {
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
