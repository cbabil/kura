//! The WebSocket `/api/stats`: a snapshot on connect, then every sample.
//! The upgrade needs a live session and an `Origin` equal to this server's,
//! since browsers do not apply CORS or SameSite rules to WebSockets alike.

use std::sync::Arc;
use std::time::Instant;

use axum::extract::State;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::Response;
use tokio::sync::broadcast::error::RecvError;

use super::AppState;
use super::guard::{error, origin_matches, session_id};

/// Upgrades to the stats stream: 403 for a foreign or missing Origin, 401
/// without a session.
pub(super) async fn stats(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    ws: WebSocketUpgrade,
) -> Response {
    if !origin_matches(&headers, &uri, state.scheme) {
        tracing::warn!("refused a stats WebSocket from another origin");
        return error(StatusCode::FORBIDDEN, "forbidden");
    }
    let Some(id) = session_id(&headers).filter(|id| state.sessions.touch(id, Instant::now()).is_some()) else {
        return error(StatusCode::UNAUTHORIZED, "signed_out");
    };
    let id = id.to_owned();
    ws.on_upgrade(move |socket| stream(socket, state, id))
}

/// Sends until the client leaves or its session ends (sign-out or idle).
/// Each sample keeps the session alive, as watching is using.
async fn stream(mut socket: WebSocket, state: Arc<AppState>, id: String) {
    let (snapshot, mut rx) = state.hub.subscribe();
    if socket.send(Message::Text(snapshot.into())).await.is_err() {
        return;
    }
    loop {
        tokio::select! {
            sample = rx.recv() => match sample {
                Ok(text) => {
                    if state.sessions.touch(&id, Instant::now()).is_none() {
                        let _ = socket.send(Message::Close(None)).await;
                        return;
                    }
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
