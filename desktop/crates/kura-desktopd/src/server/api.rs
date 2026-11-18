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

/// Runs a blocking file operation off the async threads. A failure, of the
/// task or of `f`, is logged with `what` and gives `None`.
async fn blocking<T, E>(what: &str, f: impl FnOnce() -> Result<T, E> + Send + 'static) -> Option<T>
where
    T: Send + 'static,
    E: std::fmt::Display + Send + 'static,
{
    match tokio::task::spawn_blocking(f).await {
        Ok(Ok(v)) => return Some(v),
        Ok(Err(e)) => tracing::error!("{what}: {e}"),
        Err(e) => tracing::error!("{what}: {e}"),
    }
    None
}

fn internal() -> Response {
    error(StatusCode::INTERNAL_SERVER_ERROR, "internal")
}

/// Static facts about the device.
pub(super) async fn system(State(state): State<Arc<AppState>>, _: Authed) -> Response {
    let root = state.root.clone();
    match blocking("system info", move || system::read(&root)).await {
        Some(info) => Json(info).into_response(),
        None => internal(),
    }
}

/// The user's preferences, or 404 when none are saved.
pub(super) async fn get_prefs(State(state): State<Arc<AppState>>, authed: Authed) -> Response {
    let store = state.prefs.clone();
    match blocking("loading preferences", move || store.load(authed.user.uid)).await {
        Some(Some(prefs)) => Json(prefs).into_response(),
        Some(None) => error(StatusCode::NOT_FOUND, "no_prefs"),
        None => internal(),
    }
}

/// Validates and saves the user's preferences: 204, 400 or 413.
pub(super) async fn put_prefs(State(state): State<Arc<AppState>>, authed: Authed, body: Bytes) -> Response {
    let prefs = match Prefs::parse(&body) {
        Ok(p) => p,
        Err(PrefsError::TooLarge) => return error(StatusCode::PAYLOAD_TOO_LARGE, "too_large"),
        Err(e) => return error(StatusCode::BAD_REQUEST, &e.to_string()),
    };
    let store = state.prefs.clone();
    match blocking("saving preferences", move || store.save(authed.user.uid, &prefs)).await {
        Some(()) => StatusCode::NO_CONTENT.into_response(),
        None => internal(),
    }
}
