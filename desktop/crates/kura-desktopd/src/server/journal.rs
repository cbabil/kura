//! The Console app: `GET /api/journal?lines=&unit=&priority=&after=`
//! (administrators). The helper validates the query and runs journalctl.

use std::sync::Arc;

use axum::extract::{Query, State};
use axum::response::Response;
use kura_desktop_core::actions::{Action, JournalArgs};
use serde::Deserialize;

use super::guard::{Authed, asked};
use super::{AppState, DEFAULT_LINES};

#[derive(Deserialize)]
pub(super) struct JournalQuery {
    lines: Option<u32>,
    unit: Option<String>,
    priority: Option<i32>,
    after: Option<String>,
}

/// The newest matching entries, oldest first, and the cursor after them.
pub(super) async fn read(
    State(state): State<Arc<AppState>>,
    authed: Authed,
    Query(q): Query<JournalQuery>,
) -> Response {
    let args = JournalArgs {
        lines: q.lines.unwrap_or(DEFAULT_LINES),
        unit: q.unit.unwrap_or_default(),
        priority: q.priority.unwrap_or(-1),
        after: q.after.unwrap_or_default(),
    };
    asked(&state, &authed, Action::ReadJournal, &args).await
}
