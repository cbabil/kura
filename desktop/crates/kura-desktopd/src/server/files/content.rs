//! A file's bytes: `GET /api/files/content` reads them from the agent a
//! piece at a time as the browser takes them, `PUT` hands the body to the
//! agent the same way.

use std::sync::Arc;

use axum::body::{Body, Bytes};
use axum::extract::{Query, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use futures_util::StreamExt;
use kura_desktop_core::files::{CHUNK, Reply, Request, part_name, percent_encode, split, valid_path};
use kura_desktop_core::session::new_session_id;

use super::{No, PathQuery, bad_request, link, said};
use crate::server::AppState;
use crate::server::guard::Authed;

/// What is shown in the page when asked `inline`: text as plain text and
/// pictures a browser cannot run. Anything else is only ever a download.
const SHOWN: [(&str, &str); 12] = [
    ("png", "image/png"),
    ("jpg", "image/jpeg"),
    ("jpeg", "image/jpeg"),
    ("gif", "image/gif"),
    ("webp", "image/webp"),
    ("txt", "text/plain; charset=utf-8"),
    ("md", "text/plain; charset=utf-8"),
    ("log", "text/plain; charset=utf-8"),
    ("json", "text/plain; charset=utf-8"),
    ("yaml", "text/plain; charset=utf-8"),
    ("yml", "text/plain; charset=utf-8"),
    ("conf", "text/plain; charset=utf-8"),
];

/// The content type and disposition of a file called `name`.
fn presented(name: &str, inline: bool) -> (&'static str, String) {
    let extension = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    let shown = SHOWN.iter().find(|(e, _)| inline && *e == extension);
    match shown {
        Some((_, kind)) => (kind, "inline".to_owned()),
        None => ("application/octet-stream", format!("attachment; filename*=UTF-8''{}", percent_encode(name, "-._"))),
    }
}

/// `piece` cut to what is still owed of a file of `size` from `offset`: a
/// file that grew meanwhile must not send more than was announced.
fn owed(mut piece: Vec<u8>, offset: u64, size: u64) -> Vec<u8> {
    piece.truncate(usize::try_from(size.saturating_sub(offset)).unwrap_or(usize::MAX));
    piece
}

/// A file's bytes, read from the agent a piece at a time as the browser
/// takes them.
pub(in crate::server) async fn download(
    State(state): State<Arc<AppState>>,
    authed: Authed,
    Query(q): Query<PathQuery>,
) -> Result<Response, No> {
    let path = q.path.filter(|p| valid_path(p)).ok_or_else(bad_request)?;
    let name = split(&path).ok_or_else(bad_request)?.1.to_owned();
    let link = link(&state, &authed).await?;
    let (reply, first) = said(&authed, link.ask(&Request::Read { path: path.clone(), offset: 0 }, None).await)?;
    let size = reply.size.unwrap_or(0);
    let (kind, disposition) = presented(&name, q.inline.is_some());
    // Each turn gives the piece in hand and fetches the next; a file that
    // shrinks meanwhile ends the body early, which the browser reports.
    let pieces = futures_util::stream::unfold(Some((owed(first.unwrap_or_default(), 0, size), 0u64)), move |held| {
        let (link, path) = (link.clone(), path.clone());
        async move {
            let (piece, offset) = held?;
            let next = offset + piece.len() as u64;
            if piece.is_empty() || next >= size {
                return Some((Ok(Bytes::from(piece)), None));
            }
            match link.ask(&Request::Read { path, offset: next }, None).await {
                Ok((Reply { error: None, .. }, Some(more))) => {
                    Some((Ok(Bytes::from(piece)), Some((owed(more, next, size), next))))
                }
                _ => Some((Err(std::io::Error::other("the file could not be read to its end")), None)),
            }
        }
    });
    let headers = [
        (header::CONTENT_TYPE, kind.to_owned()),
        (header::CONTENT_DISPOSITION, disposition),
        (header::CONTENT_LENGTH, size.to_string()),
    ];
    Ok((headers, Body::from_stream(pieces)).into_response())
}

/// A new file from the request's body, handed to the agent a piece at a
/// time; it appears under its name once the last piece is written. 204.
pub(in crate::server) async fn upload(
    State(state): State<Arc<AppState>>,
    authed: Authed,
    Query(q): Query<PathQuery>,
    body: Body,
) -> Result<StatusCode, No> {
    let path = q.path.filter(|p| valid_path(p)).ok_or_else(bad_request)?;
    let (folder, name) = split(&path).ok_or_else(bad_request)?;
    // This upload's own name for its part file: two of one name do not mix.
    let id = new_session_id()[..16].to_owned();
    let part = format!("{}/{}", folder.trim_end_matches('/'), part_name(name, &id));
    let link = link(&state, &authed).await?;
    let write = |offset: u64, last: bool| Request::Write { path: path.clone(), id: id.clone(), offset, last };
    let mut body = body.into_data_stream();
    let (mut held, mut offset) = (Vec::<u8>::new(), 0u64);
    while let Some(read) = body.next().await {
        let Ok(bytes) = read else {
            // The browser went away: what was written so far is not kept.
            let _ = link.ask(&Request::Delete { path: part }, None).await;
            return Err(bad_request());
        };
        held.extend_from_slice(&bytes);
        // One piece is always kept back, so the last one can say it is.
        while held.len() > CHUNK {
            let piece: Vec<u8> = held.drain(..CHUNK).collect();
            said(&authed, link.ask(&write(offset, false), Some(&piece)).await)?;
            offset += CHUNK as u64;
        }
    }
    said(&authed, link.ask(&write(offset, true), Some(&held)).await)?;
    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_piece_is_cut_to_what_was_announced() {
        assert_eq!(owed(vec![1, 2, 3], 0, 10), [1, 2, 3]);
        assert_eq!(owed(vec![1, 2, 3], 8, 10), [1, 2], "the file grew while it was read");
        assert_eq!(owed(vec![1, 2, 3], 12, 10), [0u8; 0]);
    }
}
