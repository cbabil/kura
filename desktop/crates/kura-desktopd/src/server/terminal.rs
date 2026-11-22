//! The Terminal app: the WebSocket `/api/terminal?cols=&rows=`. The helper
//! starts the signed-in user's shell and hands over its pseudo-terminal;
//! this relays it. Binary frames are the terminal's bytes, both ways. Text
//! frames are JSON: the client sends `{"type":"resize","cols":..,"rows":..}`
//! and the server `{"type":"exit"}` when the shell has ended.

use std::sync::Arc;
use std::time::Instant;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::Response;
use futures_util::stream::{SplitSink, SplitStream};
use futures_util::{SinkExt, StreamExt};
use kura_desktop_core::stats::sampler::PERIOD;
use kura_desktop_core::terminal::valid_size;
use serde::Deserialize;
use tokio::sync::OwnedSemaphorePermit;

use super::AppState;
use super::guard::{Authed, error, origin_matches, refused};
use crate::helper::Helper;
use crate::pty::Pty;

/// The largest message accepted from the client (a big paste).
const MAX_INCOMING: usize = 64 * 1024;
/// The shell's output is read this much at a time.
const CHUNK: usize = 8 * 1024;

#[derive(Deserialize)]
pub(super) struct Size {
    cols: Option<u16>,
    rows: Option<u16>,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
enum Control {
    Resize { cols: u16, rows: u16 },
}

/// Asks the helper to stop the shell when the terminal goes away, however
/// it goes: the tab closes, the session ends or the upgrade never happens.
struct Closer {
    helper: Arc<dyn Helper>,
    ticket: String,
    id: String,
    _slot: OwnedSemaphorePermit,
}

impl Drop for Closer {
    fn drop(&mut self) {
        let (helper, ticket, id) =
            (self.helper.clone(), std::mem::take(&mut self.ticket), std::mem::take(&mut self.id));
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            // An already ended shell is "not found", which is fine.
            runtime.spawn(async move {
                tracing::info!("terminal: asking the helper to close it");
                let closed = helper.close_terminal(&ticket, &id).await;
                tracing::info!(ok = closed.is_ok(), "terminal closed");
            });
        }
    }
}

/// Opens a terminal: 401 without a session, 403 for a foreign or missing
/// Origin or an account without a shell, 429 when too many are open.
pub(super) async fn terminal(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(size): Query<Size>,
    authed: Authed,
    ws: WebSocketUpgrade,
) -> Response {
    if !origin_matches(&headers, &uri, state.scheme) {
        tracing::warn!("refused a terminal WebSocket from another origin");
        return error(StatusCode::FORBIDDEN, "forbidden");
    }
    let Ok(slot) = state.terminal_slots.clone().try_acquire_owned() else {
        return error(StatusCode::TOO_MANY_REQUESTS, "busy");
    };
    let (cols, rows) = (size.cols.unwrap_or(80), size.rows.unwrap_or(24));
    let (id, master) = match state.helper.open_terminal(&authed.ticket, cols, rows).await {
        Ok(opened) => opened,
        Err(e) => return refused(&state, &authed.id, &e),
    };
    let closer = Closer { helper: state.helper.clone(), ticket: authed.ticket, id, _slot: slot };
    let pty = match Pty::new(master) {
        Ok(pty) => Arc::new(pty),
        Err(e) => {
            tracing::error!("terminal: {e}");
            return error(StatusCode::SERVICE_UNAVAILABLE, "unavailable");
        }
    };
    tracing::info!(user = %authed.user.name, "terminal opened");
    ws.max_message_size(MAX_INCOMING).max_frame_size(MAX_INCOMING).on_upgrade(move |socket| async move {
        let (sink, stream) = socket.split();
        // Each direction on its own, so a flood one way never blocks the other.
        let ended = tokio::select! {
            () = shell_to_browser(&pty, sink) => "the shell ended",
            () = browser_to_shell(&pty, stream, &state, &authed.id) => "the browser left",
        };
        tracing::info!("terminal: {ended}");
        drop(closer);
    })
}

/// Sends the shell's output until it ends, then says so.
async fn shell_to_browser(pty: &Pty, mut sink: SplitSink<WebSocket, Message>) {
    let mut buf = vec![0u8; CHUNK];
    while let Ok(n @ 1..) = pty.read(&mut buf).await {
        if sink.send(Message::Binary(buf[..n].to_vec().into())).await.is_err() {
            return;
        }
    }
    let _ = sink.send(Message::Text(r#"{"type":"exit"}"#.into())).await;
    let _ = sink.send(Message::Close(None)).await;
}

/// Types the client's input into the shell and applies its resizes, until
/// the client leaves or its session ends (checked every sampling period;
/// an open terminal keeps the session alive, as the stats stream does).
async fn browser_to_shell(pty: &Pty, mut stream: SplitStream<WebSocket>, state: &AppState, session: &str) {
    let mut check = tokio::time::interval(PERIOD);
    loop {
        tokio::select! {
            _ = check.tick() => {
                if !state.sessions.keep_alive(session, Instant::now()) {
                    return;
                }
            }
            incoming = stream.next() => match incoming {
                Some(Ok(Message::Binary(data))) => {
                    if pty.write_all(&data).await.is_err() {
                        return;
                    }
                }
                Some(Ok(Message::Text(text))) => {
                    // A size out of range is ignored, as any other message that makes no sense.
                    if let Ok(Control::Resize { cols, rows }) = serde_json::from_str(&text)
                        && valid_size(cols, rows)
                        && pty.resize(cols, rows).is_err()
                    {
                        return;
                    }
                }
                Some(Ok(Message::Close(_)) | Err(_)) | None => return,
                Some(Ok(_)) => {}
            },
        }
    }
}
