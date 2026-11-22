//! The WebSocket `/api/stats`: a snapshot on connect, then every sample.
//! The upgrade needs a live session and an `Origin` equal to this server's,
//! since browsers do not apply CORS or SameSite rules to WebSockets alike.

use std::sync::Arc;
use std::time::Instant;

use axum::extract::State;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::Response;
use kura_desktop_core::stats::sampler::PERIOD;
use tokio::sync::broadcast::error::RecvError;

/// The largest message accepted from the client.
const MAX_INCOMING: usize = 1024;

use super::AppState;
use super::guard::{Authed, error, origin_matches};

/// Upgrades to the stats stream: 401 without a session, 403 for a foreign
/// or missing Origin.
pub(super) async fn stats(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    authed: Authed,
    ws: WebSocketUpgrade,
) -> Response {
    if !origin_matches(&headers, &uri, state.scheme) {
        tracing::warn!("refused a stats WebSocket from another origin");
        return error(StatusCode::FORBIDDEN, "forbidden");
    }
    // The client only sends pings and the close frame.
    ws.max_message_size(MAX_INCOMING)
        .max_frame_size(MAX_INCOMING)
        .on_upgrade(move |socket| stream(socket, state, authed.id, authed.ticket))
}

/// How often an open desktop tells the helper its ticket is still in use.
const TICKET_PERIOD: std::time::Duration = std::time::Duration::from_secs(600);

/// Sends until the client leaves or its session ends (sign-out or idle),
/// checked every sampling period even when no sample comes. Watching keeps
/// the session alive, as watching is using, and with it the helper's
/// ticket, so both end together.
async fn stream(mut socket: WebSocket, state: Arc<AppState>, id: String, ticket: String) {
    let mut ticket_check = tokio::time::interval(TICKET_PERIOD);
    let (snapshot, mut rx) = state.hub.subscribe();
    if socket.send(Message::Text(snapshot.into())).await.is_err() {
        return;
    }
    let mut check = tokio::time::interval(PERIOD);
    loop {
        tokio::select! {
            _ = check.tick() => {
                if !state.sessions.keep_alive(&id, Instant::now()) {
                    let _ = socket.send(Message::Close(None)).await;
                    return;
                }
            }
            _ = ticket_check.tick() => {
                if state.helper.keep_alive(&ticket).await == Err(crate::helper::HelperError::SignedOut) {
                    state.sessions.remove(&id);
                    let _ = socket.send(Message::Close(None)).await;
                    return;
                }
            }
            sample = rx.recv() => match sample {
                Ok(text) => {
                    if socket.send(Message::Text(text.as_ref().into())).await.is_err() {
                        return;
                    }
                }
                Err(RecvError::Lagged(_)) => {}
                Err(RecvError::Closed) => return,
            },
            incoming = socket.recv() => match incoming {
                Some(Ok(Message::Close(_)) | Err(_)) | None => return,
                Some(Ok(_)) => {}
            },
        }
    }
}
