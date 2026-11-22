//! Updates and power: `GET /api/updates`, `POST
//! /api/updates/{check|install}` and `POST /api/power/{restart|shutdown}`.
//! The helper decides who may (everyone sees whether an update waits; only
//! administrators start one or switch the machine off) and asks systemd.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::Response;
use kura_desktop_core::actions::{Action, PowerArgs, PowerKind, UpdateArgs, UpdateKind};

use super::AppState;
use super::guard::{Authed, asked, error};

/// The installed version, the waiting one, whether a restart is due, and
/// the last update job.
pub(super) async fn status(State(state): State<Arc<AppState>>, authed: Authed) -> Response {
    asked(&state, &authed, Action::UpdateStatus, &()).await
}

/// Starts a check or an installation: 204. Nothing restarts by itself.
pub(super) async fn update(State(state): State<Arc<AppState>>, authed: Authed, Path(what): Path<String>) -> Response {
    let what = match what.as_str() {
        "check" => UpdateKind::Check,
        "install" => UpdateKind::Install,
        _ => return error(StatusCode::NOT_FOUND, "not_found"),
    };
    asked(&state, &authed, Action::StartUpdate, &UpdateArgs { what }).await
}

/// Restarts or shuts down the machine: 204, and then the connection goes.
pub(super) async fn power(State(state): State<Arc<AppState>>, authed: Authed, Path(how): Path<String>) -> Response {
    let how = match how.as_str() {
        "restart" => PowerKind::Restart,
        "shutdown" => PowerKind::Shutdown,
        _ => return error(StatusCode::NOT_FOUND, "not_found"),
    };
    tracing::warn!(user = %authed.user.name, ?how, "power asked");
    asked(&state, &authed, Action::Power, &PowerArgs { how }).await
}
