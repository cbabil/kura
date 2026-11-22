use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use kura_desktop_core::stats::Sample;
use tokio_tungstenite::tungstenite::{self, Message, client::IntoClientRequest};

use super::*;

pub(super) async fn serve(app: &TestApp) -> SocketAddr {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let service = router(app.state.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, service).await.unwrap() });
    addr
}

pub(super) type Socket = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn connect(addr: SocketAddr, origin: Option<&str>, cookie: Option<&str>) -> Result<Socket, u16> {
    connect_to(addr, "/api/stats", origin, cookie).await
}

/// Opens the WebSocket at `path`; a refused upgrade gives its status.
pub(super) async fn connect_to(
    addr: SocketAddr,
    path: &str,
    origin: Option<&str>,
    cookie: Option<&str>,
) -> Result<Socket, u16> {
    let mut req = format!("ws://{addr}{path}").into_client_request().unwrap();
    if let Some(o) = origin {
        req.headers_mut().insert("origin", o.parse().unwrap());
    }
    if let Some(c) = cookie {
        req.headers_mut().insert("cookie", c.parse().unwrap());
    }
    match tokio_tungstenite::connect_async(req).await {
        Ok((socket, _)) => Ok(socket),
        Err(tungstenite::Error::Http(res)) => Err(res.status().as_u16()),
        Err(e) => panic!("{e}"),
    }
}

async fn next_json(socket: &mut Socket) -> serde_json::Value {
    let msg = tokio::time::timeout(Duration::from_secs(5), socket.next()).await.unwrap().unwrap().unwrap();
    json(msg.to_text().unwrap())
}

fn sample(t: i64) -> Sample {
    Sample { t, cpu: 12.5, temp_c: Some(40.0), ..Sample::default() }
}

#[tokio::test]
async fn the_upgrade_needs_this_origin_and_a_session() {
    let app = TestApp::new();
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let here = format!("https://{addr}");
    assert_eq!(connect(addr, None, Some(&cookie)).await.unwrap_err(), 403, "missing Origin");
    assert_eq!(connect(addr, Some("https://evil.example"), Some(&cookie)).await.unwrap_err(), 403);
    assert_eq!(connect(addr, Some(&format!("http://{addr}")), Some(&cookie)).await.unwrap_err(), 403);
    assert_eq!(connect(addr, Some(&here), None).await.unwrap_err(), 401);
    assert_eq!(connect(addr, Some(&here), Some("__Host-kura=forged")).await.unwrap_err(), 401);
    assert!(connect(addr, Some(&here), Some(&cookie)).await.is_ok());
}

#[tokio::test]
async fn snapshot_then_samples_until_sign_out() {
    let app = TestApp::new();
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    app.state.hub.record(sample(1), vec![], None);
    let mut socket = connect(addr, Some(&format!("https://{addr}")), Some(&cookie)).await.unwrap();
    let snap = next_json(&mut socket).await;
    assert_eq!(snap["type"], "snapshot");
    assert_eq!(snap["history"]["1h"][0]["t"], 1);
    app.state.hub.record(sample(2), vec![], None);
    let msg = next_json(&mut socket).await;
    assert_eq!(
        (msg["type"].as_str(), msg["sample"]["t"].as_i64(), msg["sample"]["tempC"].as_f64()),
        (Some("sample"), Some(2), Some(40.0))
    );
    socket.send(Message::Ping(vec![1].into())).await.unwrap();

    // No sample comes after sign-out; the periodic check still ends it.
    app.send(request("POST", "/api/logout", Some(&cookie), None)).await;
    let end = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            match socket.next().await {
                Some(Ok(Message::Pong(_))) => {}
                other => return other,
            }
        }
    })
    .await
    .unwrap();
    assert!(matches!(end, Some(Ok(Message::Close(_))) | None | Some(Err(_))), "{end:?}");
}

#[tokio::test]
async fn the_stream_stops_when_the_client_leaves() {
    let app = TestApp::new();
    let addr = serve(&app).await;
    let cookie = app.sign_in("kura").await;
    let mut socket = connect(addr, Some(&format!("https://{addr}")), Some(&cookie)).await.unwrap();
    next_json(&mut socket).await;
    socket.close(None).await.unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    app.state.hub.record(sample(4), vec![], None);
}
