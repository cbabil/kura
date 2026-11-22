//! The Files app: `GET /api/files` (a folder), `POST /api/files` (one
//! change), `GET /api/files/trash`, and `GET`/`PUT /api/files/content` (a
//! download, an upload). Everything is done by the user's own agent
//! (`kura-agent`, ADR-031), so the kernel decides what they may touch; this
//! file only carries the requests, and `content` the bytes.

mod content;

use std::sync::Arc;

use axum::Json;
use axum::body::Bytes;
use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use kura_desktop_core::files::{Failure, Reply, Request};
use serde::Deserialize;

use super::AppState;
use super::guard::{Authed, error, refused};
use crate::files::{Answer, FilesLink};

/// The largest body of a change (two paths at most).
pub(super) const MAX_BYTES: usize = 16 * 1024;

#[derive(Deserialize)]
pub(super) struct PathQuery {
    path: Option<String>,
    inline: Option<String>,
}

pub(super) use content::{download, upload};

/// The answer to send instead of the one hoped for (boxed: it is large).
pub(super) struct No(Box<Response>);

impl IntoResponse for No {
    fn into_response(self) -> Response {
        *self.0
    }
}

fn no(status: StatusCode, code: &str) -> No {
    No(Box::new(error(status, code)))
}

fn bad_request() -> No {
    no(StatusCode::BAD_REQUEST, "bad_request")
}

fn failed(why: Failure) -> No {
    match why {
        Failure::NotFound => no(StatusCode::NOT_FOUND, "not_found"),
        Failure::Denied => no(StatusCode::FORBIDDEN, "denied"),
        Failure::Exists => no(StatusCode::CONFLICT, "exists"),
        Failure::Invalid => bad_request(),
        Failure::OtherVolume => no(StatusCode::CONFLICT, "other_volume"),
        Failure::Io => no(StatusCode::INTERNAL_SERVER_ERROR, "failed"),
    }
}

/// The session's link to its agent, or the answer to why there is none.
async fn link(state: &AppState, authed: &Authed) -> Result<Arc<FilesLink>, No> {
    let got = state.files.get(state.helper.as_ref(), &authed.id, &authed.ticket).await;
    got.map_err(|e| No(Box::new(refused(state, &authed.id, &e))))
}

/// What the agent said: a refusal as itself; a link that broke as
/// unavailable (the next request starts a new agent).
fn said(authed: &Authed, done: std::io::Result<Answer>) -> Result<Answer, No> {
    match done {
        Ok((Reply { error: Some(why), .. }, _)) => Err(failed(why)),
        Ok(answer) => Ok(answer),
        Err(e) => {
            tracing::warn!(user = authed.user.name, "the file agent is gone: {e}");
            Err(no(StatusCode::SERVICE_UNAVAILABLE, "unavailable"))
        }
    }
}

/// Asks what a window asks again every few seconds. Not waited for behind
/// a long copy (429 instead), and few are built at once: a listing is large.
async fn look(state: &AppState, authed: &Authed, link: &FilesLink, request: &Request) -> Result<Reply, No> {
    let _few = state.files.listings.acquire().await.map_err(|_| no(StatusCode::SERVICE_UNAVAILABLE, "unavailable"))?;
    match link.ask_if_free(request).await.transpose() {
        Some(done) => Ok(said(authed, done)?.0),
        None => Err(no(StatusCode::TOO_MANY_REQUESTS, "busy")),
    }
}

/// A folder's entries; the home folder when no path is given.
pub(super) async fn list(
    State(state): State<Arc<AppState>>,
    authed: Authed,
    Query(q): Query<PathQuery>,
) -> Result<Response, No> {
    let link = link(&state, &authed).await?;
    let path = q.path.unwrap_or_else(|| link.home.clone());
    let reply = look(&state, &authed, &link, &Request::List { path: path.clone() }).await?;
    let entries = reply.entries.unwrap_or_default();
    let folder =
        serde_json::json!({ "path": path, "home": link.home, "entries": entries, "truncated": reply.truncated });
    Ok(Json(folder).into_response())
}

/// What is in the user's trash.
pub(super) async fn trash(State(state): State<Arc<AppState>>, authed: Authed) -> Result<Response, No> {
    let link = link(&state, &authed).await?;
    let reply = look(&state, &authed, &link, &Request::ListTrash).await?;
    Ok(Json(serde_json::json!({ "items": reply.trash.unwrap_or_default() })).into_response())
}

/// One change, as the agent's own request: make a folder, rename, copy,
/// delete, trash, restore, empty the trash. 204 when done.
pub(super) async fn change(State(state): State<Arc<AppState>>, authed: Authed, body: Bytes) -> Result<StatusCode, No> {
    let request = match serde_json::from_slice::<Request>(&body) {
        Ok(
            Request::Hello | Request::List { .. } | Request::ListTrash | Request::Read { .. } | Request::Write { .. },
        )
        | Err(_) => return Err(bad_request()),
        Ok(change) => change,
    };
    let link = link(&state, &authed).await?;
    said(&authed, link.ask(&request, None).await)?;
    Ok(StatusCode::NO_CONTENT)
}
