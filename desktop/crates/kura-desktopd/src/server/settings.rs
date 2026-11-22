//! Settings: `GET /api/settings` (administrators), `POST /api/settings` with
//! one change as its body (administrators), and `POST /api/password` for
//! one's own password. The helper checks every value and runs the change.

use std::sync::Arc;

use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::Response;
use kura_desktop_core::actions::{Action, OwnPasswordArgs};
use kura_desktop_core::settings::Change;

use super::AppState;
use super::guard::{Authed, asked, error};

/// The largest change accepted (the longest is a user with a password).
pub(super) const MAX_BYTES: usize = 4096;

/// Everything Settings shows.
pub(super) async fn read(State(state): State<Arc<AppState>>, authed: Authed) -> Response {
    asked(&state, &authed, Action::ReadSettings, &()).await
}

/// Makes one change: 204, or 400 for a body that is not a change.
pub(super) async fn change(State(state): State<Arc<AppState>>, authed: Authed, body: Bytes) -> Response {
    let Ok(change) = serde_json::from_slice::<Change>(&body) else {
        return error(StatusCode::BAD_REQUEST, "bad_request");
    };
    tracing::info!(user = %authed.user.name, change = change.name(), "setting asked");
    asked(&state, &authed, Action::ChangeSetting, &change).await
}

/// Changes the signed-in user's own password, given the current one.
pub(super) async fn password(State(state): State<Arc<AppState>>, authed: Authed, body: Bytes) -> Response {
    let Ok(args) = serde_json::from_slice::<OwnPasswordArgs>(&body) else {
        return error(StatusCode::BAD_REQUEST, "bad_request");
    };
    asked(&state, &authed, Action::ChangeOwnPassword, &args).await
}
