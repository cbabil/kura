//! `GET /api/system` and `GET`/`PUT /api/prefs`.

use std::sync::Arc;

use axum::Json;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use kura_desktop_core::prefs::{Prefs, PrefsError};
use kura_desktop_core::stats::system;

use super::AppState;
use super::guard::{Authed, error};

/// Runs a blocking file operation off the async threads.
async fn blocking<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> Option<T> {
    tokio::task::spawn_blocking(f).await.inspect_err(|e| tracing::error!("blocking task failed: {e}")).ok()
}

fn internal(what: &str, e: impl std::fmt::Display) -> Response {
    tracing::error!("{what}: {e}");
    error(StatusCode::INTERNAL_SERVER_ERROR, "internal")
}

/// Static facts about the device.
pub(super) async fn system(State(state): State<Arc<AppState>>, _: Authed) -> Response {
    let root = state.root.clone();
    match blocking(move || system::read(&root)).await {
        Some(Ok(info)) => Json(info).into_response(),
        Some(Err(e)) => internal("system info", e),
        None => internal("system info", "task failed"),
    }
}

/// The user's preferences, or 404 when none are saved.
pub(super) async fn get_prefs(State(state): State<Arc<AppState>>, Authed(user): Authed) -> Response {
    let store = state.prefs.clone();
    match blocking(move || store.load(user.uid)).await {
        Some(Ok(Some(prefs))) => Json(prefs).into_response(),
        Some(Ok(None)) => error(StatusCode::NOT_FOUND, "no_prefs"),
        Some(Err(e)) => internal("loading preferences", e),
        None => internal("loading preferences", "task failed"),
    }
}

/// Validates and saves the user's preferences: 204, 400 or 413.
pub(super) async fn put_prefs(State(state): State<Arc<AppState>>, Authed(user): Authed, body: Bytes) -> Response {
    let prefs = match Prefs::parse(&body) {
        Ok(p) => p,
        Err(PrefsError::TooLarge) => return error(StatusCode::PAYLOAD_TOO_LARGE, "too_large"),
        Err(e) => return error(StatusCode::BAD_REQUEST, &e.to_string()),
    };
    let store = state.prefs.clone();
    match blocking(move || store.save(user.uid, &prefs)).await {
        Some(Ok(())) => StatusCode::NO_CONTENT.into_response(),
        Some(Err(e)) => internal("saving preferences", e),
        None => internal("saving preferences", "task failed"),
    }
}
