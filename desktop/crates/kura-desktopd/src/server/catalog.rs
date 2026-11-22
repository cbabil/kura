//! The App Catalog: `GET /api/catalog` (the apps and the last job) and
//! `POST /api/catalog` (install, update or remove one). The helper decides
//! who may (administrators) and what is in the catalog; a job installs.

use std::sync::Arc;

use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::Response;
use kura_desktop_core::actions::Action;
use kura_desktop_core::catalog::AppChange;

use super::AppState;
use super::guard::{Authed, asked, error};

/// The largest body of a change.
pub(super) const MAX_BYTES: usize = 1024;

/// The catalog's apps, what is installed, and the last job with its output.
pub(super) async fn read(State(state): State<Arc<AppState>>, authed: Authed) -> Response {
    asked(&state, &authed, Action::ReadCatalog, &()).await
}

/// Starts the installation, update or removal of one app: 204.
pub(super) async fn change(State(state): State<Arc<AppState>>, authed: Authed, body: Bytes) -> Response {
    let Ok(change) = serde_json::from_slice::<AppChange>(&body) else {
        return error(StatusCode::BAD_REQUEST, "bad_request");
    };
    asked(&state, &authed, Action::ChangeApp, &change).await
}
