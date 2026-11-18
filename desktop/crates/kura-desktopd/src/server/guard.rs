//! Request guards: the session cookie, the `Origin` check and the CSRF rule
//! for requests that change something.

use std::sync::Arc;
use std::time::Instant;

use axum::Json;
use axum::extract::{FromRequestParts, Request, State};
use axum::http::request::Parts;
use axum::http::{HeaderMap, Method, StatusCode, Uri, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use kura_desktop_core::session::SessionUser;

use super::AppState;

/// The session cookie's name; `__Host-` makes browsers demand Secure, no
/// Domain and `Path=/`.
pub const COOKIE: &str = "__Host-kura";
/// The header the interface sends on every POST and PUT.
pub const REQUEST_HEADER: &str = "x-kura-request";

/// A JSON error body `{"error": code}`.
pub fn error(status: StatusCode, code: &str) -> Response {
    (status, Json(serde_json::json!({ "error": code }))).into_response()
}

/// The session id from the `Cookie` headers.
pub fn session_id(headers: &HeaderMap) -> Option<&str> {
    headers
        .get_all(header::COOKIE)
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(';'))
        .find_map(|pair| pair.trim().strip_prefix(COOKIE)?.strip_prefix('='))
        .filter(|id| !id.is_empty())
}

/// The `Set-Cookie` value for a new session, or one that clears it.
pub fn set_cookie(id: Option<&str>) -> String {
    let attrs = "Path=/; HttpOnly; Secure; SameSite=Strict";
    match id {
        Some(id) => format!("{COOKIE}={id}; {attrs}"),
        None => format!("{COOKIE}=; Max-Age=0; {attrs}"),
    }
}

/// True when `Origin` is exactly the origin this request was sent to.
/// A missing `Origin` fails.
pub fn origin_matches(headers: &HeaderMap, uri: &Uri, scheme: &str) -> bool {
    let host = headers.get(header::HOST).and_then(|h| h.to_str().ok()).or_else(|| uri.authority().map(|a| a.as_str()));
    let origin = headers.get(header::ORIGIN).and_then(|o| o.to_str().ok());
    match (origin, host) {
        (Some(origin), Some(host)) => origin.eq_ignore_ascii_case(&format!("{scheme}://{host}")),
        _ => false,
    }
}

/// Refuses POST, PUT, PATCH and DELETE without `X-Kura-Request: 1` or with
/// a foreign or missing `Origin` (403).
pub async fn csrf(State(state): State<Arc<AppState>>, req: Request, next: Next) -> Response {
    let safe = matches!(*req.method(), Method::GET | Method::HEAD | Method::OPTIONS);
    if !safe {
        let marked = req.headers().get(REQUEST_HEADER).is_some_and(|v| v == "1");
        if !marked || !origin_matches(req.headers(), req.uri(), state.scheme) {
            tracing::warn!(path = req.uri().path(), marked, "refused a request from another origin");
            return error(StatusCode::FORBIDDEN, "forbidden");
        }
    }
    next.run(req).await
}

/// The signed-in user and their session id; extracting it fails with 401
/// without a live session.
pub struct Authed {
    pub id: String,
    pub user: SessionUser,
}

impl FromRequestParts<Arc<AppState>> for Authed {
    type Rejection = Response;

    async fn from_request_parts(parts: &mut Parts, state: &Arc<AppState>) -> Result<Self, Response> {
        session_id(&parts.headers)
            .and_then(|id| Some(Authed { id: id.to_owned(), user: state.sessions.touch(id, Instant::now())? }))
            .ok_or_else(|| error(StatusCode::UNAUTHORIZED, "signed_out"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    fn headers(pairs: &[(&'static str, &'static str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.append(*k, HeaderValue::from_static(v));
        }
        h
    }

    #[test]
    fn finds_the_session_cookie() {
        let cases = [
            (vec![("cookie", "__Host-kura=abc")], Some("abc")),
            (vec![("cookie", "a=1; __Host-kura=abc; b=2")], Some("abc")),
            (vec![("cookie", "a=1"), ("cookie", "__Host-kura=xyz")], Some("xyz")),
            (vec![("cookie", "__Host-kurax=abc")], None),
            (vec![("cookie", "__Host-kura=")], None),
            (vec![], None),
        ];
        for (pairs, want) in cases {
            assert_eq!(session_id(&headers(&pairs)), want, "{pairs:?}");
        }
    }

    #[test]
    fn cookie_attributes() {
        assert_eq!(set_cookie(Some("id")), "__Host-kura=id; Path=/; HttpOnly; Secure; SameSite=Strict");
        assert!(set_cookie(None).contains("Max-Age=0"));
    }

    #[test]
    fn origin_must_equal_the_serving_origin() {
        let uri: Uri = "/api/login".parse().unwrap();
        let h2: Uri = "https://kura.local/api/login".parse().unwrap();
        let cases = [
            (vec![("host", "kura.local"), ("origin", "https://kura.local")], &uri, true),
            (vec![("host", "kura.local"), ("origin", "https://KURA.local")], &uri, true),
            (vec![("host", "kura.local:8443"), ("origin", "https://kura.local:8443")], &uri, true),
            (vec![("host", "kura.local"), ("origin", "http://kura.local")], &uri, false),
            (vec![("host", "kura.local"), ("origin", "https://evil.example")], &uri, false),
            (vec![("host", "kura.local"), ("origin", "null")], &uri, false),
            (vec![("host", "kura.local")], &uri, false),
            (vec![("origin", "https://kura.local")], &uri, false),
            (vec![("origin", "https://kura.local")], &h2, true),
        ];
        for (pairs, uri, want) in cases {
            assert_eq!(origin_matches(&headers(&pairs), uri, "https"), want, "{pairs:?}");
        }
    }
}
