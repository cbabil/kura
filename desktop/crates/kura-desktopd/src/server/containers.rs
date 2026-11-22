//! The Containers app: `GET /api/containers`, `POST
//! /api/containers/{id}/{start|stop|restart}` and `GET
//! /api/containers/{id}/logs`. The helper checks who may do what and talks
//! to Docker; its JSON is passed on as it is.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use kura_desktop_core::actions::{Action, ContainerArgs, LogsArgs};
use kura_desktop_core::containers::ContainerAction;
use serde::Deserialize;

use super::guard::{Authed, asked, error};
use super::{AppState, DEFAULT_LINES};

/// Every container, for any signed-in user.
pub(super) async fn list(State(state): State<Arc<AppState>>, authed: Authed) -> Response {
    asked(&state, &authed, Action::ListContainers, &()).await
}

/// Starts, stops or restarts a container (administrators): 204.
pub(super) async fn act(
    State(state): State<Arc<AppState>>,
    authed: Authed,
    Path((id, action)): Path<(String, String)>,
) -> Response {
    let Some(action) = ContainerAction::parse(&action) else {
        return error(StatusCode::BAD_REQUEST, "bad_request");
    };
    asked(&state, &authed, Action::ControlContainer, &ContainerArgs { id, action }).await
}

#[derive(Deserialize)]
pub(super) struct LogsQuery {
    lines: Option<u32>,
}

/// A container's last lines (administrators).
pub(super) async fn logs(
    State(state): State<Arc<AppState>>,
    authed: Authed,
    Path(id): Path<String>,
    Query(q): Query<LogsQuery>,
) -> Response {
    asked(&state, &authed, Action::ContainerLogs, &LogsArgs { id, lines: q.lines.unwrap_or(DEFAULT_LINES) }).await
}
