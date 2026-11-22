use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message;

use super::ws::{Socket, connect_to, serve};
use super::*;

async fn open(app: &TestApp, addr: SocketAddr, cookie: &str, query: &str) -> Result<Socket, u16> {
    let _ = app;
    connect_to(addr, &format!("/api/terminal{query}"), Some(&format!("https://{addr}")), Some(cookie)).await
}

/// Reads until the shell's output contains `want`; `None` when the terminal
/// ends first. Also gives the last control message seen.
async fn read_until(socket: &mut Socket, want: &str) -> (Option<String>, Option<String>) {
    read_while(socket, |seen| !seen.contains(want)).await
}

/// Reads while `more` says the output so far is not enough.
async fn read_while(socket: &mut Socket, more: impl Fn(&str) -> bool) -> (Option<String>, Option<String>) {
    let mut seen = String::new();
    let mut control = None;
    let read = async {
        while let Some(Ok(msg)) = socket.next().await {
            match msg {
                Message::Binary(bytes) => seen.push_str(&String::from_utf8_lossy(&bytes)),
                Message::Text(text) => control = Some(text.to_string()),
                Message::Close(_) => break,
                _ => {}
            }
            if !more(&seen) {
                return true;
            }
        }
        false
    };
    let found = tokio::time::timeout(Duration::from_secs(10), read).await.unwrap_or(false);
    (found.then_some(seen), control)
}

async fn type_in(socket: &mut Socket, text: &str) {
    socket.send(Message::Binary(text.as_bytes().to_vec().into())).await.unwrap();
}

#[tokio::test]
async fn the_upgrade_needs_this_origin_a_session_and_a_shell() {
    let app = TestApp::with_guests();
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let here = format!("https://{addr}");
    let path = "/api/terminal";
    assert_eq!(connect_to(addr, path, None, Some(&cookie)).await.unwrap_err(), 403, "missing Origin");
    assert_eq!(connect_to(addr, path, Some("https://evil.example"), Some(&cookie)).await.unwrap_err(), 403);
    assert_eq!(connect_to(addr, path, Some(&here), None).await.unwrap_err(), 401);
    assert_eq!(open(&app, addr, &cookie, "?cols=0").await.unwrap_err(), 400);
    assert_eq!(open(&app, addr, &cookie, "?rows=900").await.unwrap_err(), 400);
    let noshell = app.sign_in("noshell").await;
    assert_eq!(open(&app, addr, &noshell, "").await.unwrap_err(), 403);
    assert!(open(&app, addr, &cookie, "").await.is_ok());
    assert!(
        open(&app, addr, &app.sign_in("guest").await, "").await.is_ok(),
        "a terminal is not for administrators only"
    );
}

#[tokio::test]
async fn types_into_a_real_shell_and_resizes_it() {
    let app = TestApp::new();
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let mut socket = open(&app, addr, &cookie, "?cols=90&rows=20").await.unwrap();
    type_in(&mut socket, "echo sum-$((40+2))\n").await;
    assert!(read_until(&mut socket, "sum-42").await.0.is_some());
    type_in(&mut socket, "stty size\n").await;
    // Up to the next prompt: while it draws one, an old readline (macOS's sh)
    // reads the window size and writes it back, undoing a resize that lands
    // in between. Every terminal has that race; the test must not provoke it.
    let prompt_after_size = |seen: &str| seen.split_once("20 90").is_some_and(|(_, rest)| rest.contains("$ "));
    assert!(
        read_while(&mut socket, |seen| !prompt_after_size(seen)).await.0.is_some(),
        "the size asked for at opening"
    );
    socket.send(Message::Text(r#"{"type":"resize","cols":132,"rows":43}"#.into())).await.unwrap();
    socket.send(Message::Text("not json".into())).await.unwrap();
    type_in(&mut socket, "stty size\n").await;
    assert!(read_until(&mut socket, "43 132").await.0.is_some());

    type_in(&mut socket, "exit\n").await;
    let (output, control) = read_until(&mut socket, "never printed").await;
    assert_eq!((output, control.as_deref()), (None, Some(r#"{"type":"exit"}"#)));
}

#[tokio::test]
async fn a_terminal_ends_with_its_session_and_ignores_a_bad_resize() {
    let app = TestApp::new();
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let mut socket = open(&app, addr, &cookie, "").await.unwrap();
    type_in(&mut socket, "echo up\n").await;
    assert!(read_until(&mut socket, "up").await.0.is_some());
    app.send(request("POST", "/api/logout", Some(&cookie), None)).await;
    assert_eq!(read_until(&mut socket, "never printed").await.0, None, "closed within a sampling period");

    let cookie = app.sign_in("kura").await;
    let mut socket = open(&app, addr, &cookie, "").await.unwrap();
    socket.send(Message::Text(r#"{"type":"resize","cols":0,"rows":43}"#.into())).await.unwrap();
    type_in(&mut socket, "echo still-$((1+1))\n").await;
    assert!(read_until(&mut socket, "still-2").await.0.is_some());
}

#[tokio::test]
async fn open_terminals_are_counted_and_released() {
    let app = TestApp::with(|s| s.terminal_slots = Arc::new(tokio::sync::Semaphore::new(1)));
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let first = open(&app, addr, &cookie, "").await.unwrap();
    assert_eq!(open(&app, addr, &cookie, "").await.unwrap_err(), 429);
    drop(first);
    let again = async {
        loop {
            if let Ok(socket) = open(&app, addr, &cookie, "").await {
                return socket;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    };
    tokio::time::timeout(Duration::from_secs(10), again).await.expect("the slot comes back when the client leaves");
}
