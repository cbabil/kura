//! The Browser app (ADR-036): the WebSocket `/api/browser`. The helper
//! starts the signed-in person's own Chromium, as them, and hands over a
//! connection to its VNC server; this relays it to the page, bytes as they
//! are, in binary frames both ways (noVNC speaks RFB over them). Text
//! frames mean nothing and are dropped.

use std::os::fd::OwnedFd;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::State;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::Response;
use futures_util::stream::{SplitSink, SplitStream};
use futures_util::{SinkExt, StreamExt};
use kura_desktop_core::actions::Action;
use kura_desktop_core::stats::sampler::PERIOD;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};

use super::AppState;
use super::guard::{Authed, asked, error, origin_matches, refused};
use crate::helper::HelperError;

/// The largest message accepted from the page (a clipboard paste).
const MAX_INCOMING: usize = 256 * 1024;
/// The screen's updates are read this much at a time.
const CHUNK: usize = 64 * 1024;
/// How often the helper is asked whether the sign-in still holds: a
/// changed password or a removed account ends the view.
const RECHECK: Duration = Duration::from_secs(60);

/// Opens the person's own browser: 401 without a session, 403 for a foreign
/// or missing Origin or an account without a login shell, 429 with too many
/// views, 503 when it does not start.
pub(super) async fn browser(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    authed: Authed,
    ws: WebSocketUpgrade,
) -> Response {
    if !origin_matches(&headers, &uri, state.scheme) {
        tracing::warn!("refused a browser WebSocket from another origin");
        return error(StatusCode::FORBIDDEN, "forbidden");
    }
    let Ok(slot) = state.browser_slots.clone().try_acquire_owned() else {
        return error(StatusCode::TOO_MANY_REQUESTS, "busy");
    };
    let vnc = match state.helper.open_browser(&authed.ticket).await {
        Ok(fd) => fd,
        Err(e) => return refused(&state, &authed.id, &e),
    };
    let vnc = match unix_stream(vnc) {
        Ok(stream) => stream,
        Err(e) => {
            tracing::error!("browser: {e}");
            return error(StatusCode::SERVICE_UNAVAILABLE, "unavailable");
        }
    };
    tracing::info!(user = %authed.user.name, "browser opened");
    ws.max_message_size(MAX_INCOMING).max_frame_size(MAX_INCOMING).on_upgrade(move |socket| async move {
        let (sink, stream) = socket.split();
        let (from_vnc, to_vnc) = vnc.into_split();
        // Each direction on its own, so a flood one way never blocks the other.
        let ended = tokio::select! {
            () = vnc_to_page(from_vnc, sink) => "the browser ended",
            () = page_to_vnc(to_vnc, stream, &state, &authed) => "the page left",
        };
        tracing::info!(user = %authed.user.name, "browser closed: {ended}");
        drop(slot);
    })
}

/// Quits the person's own browser: 204.
pub(super) async fn stop(State(state): State<Arc<AppState>>, authed: Authed) -> Response {
    asked(&state, &authed, Action::BrowserStop, &()).await
}

/// The helper's connection, as the runtime's own socket.
fn unix_stream(fd: OwnedFd) -> std::io::Result<UnixStream> {
    let stream = std::os::unix::net::UnixStream::from(fd);
    stream.set_nonblocking(true)?;
    UnixStream::from_std(stream)
}

/// Sends the screen to the page until the browser ends, then closes.
async fn vnc_to_page(mut vnc: OwnedReadHalf, mut sink: SplitSink<WebSocket, Message>) {
    let mut buf = vec![0u8; CHUNK];
    while let Ok(n @ 1..) = vnc.read(&mut buf).await {
        if sink.send(Message::Binary(buf[..n].to_vec().into())).await.is_err() {
            return;
        }
    }
    let _ = sink.send(Message::Close(None)).await;
}

/// Passes the page's keys, pointer and clipboard on, until the page leaves
/// or its session ends (an open view keeps the session alive, as the
/// terminal does).
async fn page_to_vnc(mut vnc: OwnedWriteHalf, mut stream: SplitStream<WebSocket>, state: &AppState, authed: &Authed) {
    let mut check = tokio::time::interval(PERIOD);
    let mut recheck = tokio::time::interval(RECHECK);
    recheck.tick().await;
    loop {
        tokio::select! {
            _ = check.tick() => {
                if !state.sessions.keep_alive(&authed.id, Instant::now()) {
                    return;
                }
            }
            _ = recheck.tick() => {
                // Only a sign-in that has ended ends the view: a helper that is
                // restarting (an upgrade) or slow to answer does not.
                if let Err(HelperError::SignedOut) = state.helper.keep_alive(&authed.ticket).await {
                    state.sessions.remove(&authed.id);
                    return;
                }
            }
            incoming = stream.next() => match incoming {
                Some(Ok(Message::Binary(data))) => {
                    if vnc.write_all(&data).await.is_err() {
                        return;
                    }
                }
                Some(Ok(Message::Close(_)) | Err(_)) | None => return,
                Some(Ok(_)) => {}
            },
        }
    }
}
