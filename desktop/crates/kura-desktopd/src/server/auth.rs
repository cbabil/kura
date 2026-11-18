//! `POST /api/login`, `POST /api/logout` and `GET /api/session`.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use axum::Json;
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use kura_desktop_core::accounts::Accounts;
use kura_desktop_core::auth::{AuthOutcome, MAX_PASSWORD_BYTES, valid_user_name};
use kura_desktop_core::ratelimit::login_keys;
use kura_desktop_core::session::SessionUser;
use serde::Deserialize;
use zeroize::Zeroizing;

use super::AppState;
use super::guard::{Authed, error, session_id, set_cookie};

#[derive(Deserialize)]
pub(super) struct LoginRequest {
    user: String,
    password: Zeroizing<String>,
}

fn user_body(user: &SessionUser) -> Json<serde_json::Value> {
    Json(serde_json::json!({ "user": user }))
}

/// 200 with the user, or 401 when signed out.
pub(super) async fn session(Authed(user): Authed) -> Response {
    user_body(&user).into_response()
}

/// Checks the password through the helper. 200 and a cookie on success;
/// 401 wrong, 403 expired, 429 rate-limited (with `Retry-After`), 503 when
/// the helper cannot be reached. The same refusal for every wrong name or
/// password, so user names cannot be probed.
pub(super) async fn login(
    State(state): State<Arc<AppState>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    body: axum::body::Bytes,
) -> Response {
    let Ok(req) = serde_json::from_slice::<LoginRequest>(&body) else {
        return error(StatusCode::BAD_REQUEST, "bad_request");
    };
    let ip = peer.ip().to_canonical().to_string();
    let shown_user = if valid_user_name(&req.user) { req.user.as_str() } else { "(invalid)" };
    let attempt = match state.limiter.begin(&login_keys(&ip, shown_user), Instant::now()) {
        Ok(a) => a,
        Err(wait) => {
            tracing::warn!(%ip, user = shown_user, "sign-in rate limited");
            let mut res = error(StatusCode::TOO_MANY_REQUESTS, "rate");
            res.headers_mut().insert(header::RETRY_AFTER, wait.into());
            return res;
        }
    };
    let well_formed = valid_user_name(&req.user) && req.password.len() <= MAX_PASSWORD_BYTES;
    let outcome =
        if well_formed { state.helper.authenticate(&req.user, &req.password).await } else { Ok(AuthOutcome::Wrong) };
    match outcome {
        Ok(AuthOutcome::Ok { admin }) => match start_session(&state, &req.user, admin) {
            Some((id, user)) => {
                state.limiter.succeeded(attempt);
                tracing::info!(%ip, user = %user.name, "signed in");
                ([(header::SET_COOKIE, set_cookie(Some(&id)))], user_body(&user)).into_response()
            }
            None => {
                tracing::error!(%ip, user = shown_user, "signed in but has no local account");
                error(StatusCode::UNAUTHORIZED, "wrong")
            }
        },
        Ok(AuthOutcome::Wrong) => {
            tracing::warn!(%ip, user = shown_user, "sign-in refused");
            error(StatusCode::UNAUTHORIZED, "wrong")
        }
        Ok(AuthOutcome::Expired) => {
            state.limiter.succeeded(attempt);
            tracing::info!(%ip, user = shown_user, "sign-in refused: password must be changed");
            error(StatusCode::FORBIDDEN, "expired")
        }
        Err(e) => {
            state.limiter.succeeded(attempt);
            tracing::error!(%ip, "{e}");
            error(StatusCode::SERVICE_UNAVAILABLE, "unavailable")
        }
    }
}

/// Creates the session for a checked user; `None` without a uid.
fn start_session(state: &AppState, name: &str, admin: bool) -> Option<(String, SessionUser)> {
    let uid = Accounts::load(&state.root).by_name(name).map(|a| a.uid).or(state.fallback_uid)?;
    let user = SessionUser { name: name.to_owned(), uid, admin };
    Some((state.sessions.create(user.clone(), Instant::now()), user))
}

/// Ends the session, if any, and clears the cookie. Always 204.
pub(super) async fn logout(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    if let Some(id) = session_id(&headers) {
        state.sessions.remove(id);
    }
    (StatusCode::NO_CONTENT, [(header::SET_COOKIE, set_cookie(None))]).into_response()
}
