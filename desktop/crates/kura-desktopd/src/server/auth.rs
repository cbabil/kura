//! `POST /api/login`, `POST /api/logout` and `GET /api/session`.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use axum::Json;
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use kura_desktop_core::accounts::Accounts;
use kura_desktop_core::auth::{AuthOutcome, valid_user_name, well_formed};
use kura_desktop_core::ratelimit::{ip_key, login_keys};
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
pub(super) async fn session(authed: Authed) -> Response {
    user_body(&authed.user).into_response()
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
    let ip = ip_key(peer.ip());
    let shown_user = if valid_user_name(&req.user) { req.user.as_str() } else { "(invalid)" };
    let attempt = match state.limiter.begin(login_keys(&ip, shown_user), Instant::now()) {
        Ok(a) => a,
        Err(wait) => {
            tracing::warn!(%ip, user = shown_user, "sign-in rate limited");
            return too_many(wait);
        }
    };
    let asked = ask(&state, &req).await;
    if matches!(asked, Asked::Done(AuthOutcome::Wrong)) {
        // The failure delay PAM no longer applies, outside the helper's slots.
        tokio::time::sleep(state.fail_delay).await;
    }
    let log = |msg: &str| tracing::warn!(%ip, user = shown_user, "{msg}");
    match asked {
        Asked::Done(AuthOutcome::Ok { admin }) => match start_session(&state, &req.user, admin) {
            Some((id, user)) => {
                state.limiter.succeeded(attempt);
                tracing::info!(%ip, user = %user.name, "signed in");
                ([(header::SET_COOKIE, set_cookie(Some(&id)))], user_body(&user)).into_response()
            }
            None => {
                log("signed in but has no local account");
                error(StatusCode::UNAUTHORIZED, "wrong")
            }
        },
        Asked::Done(AuthOutcome::Wrong) => {
            log("sign-in refused");
            error(StatusCode::UNAUTHORIZED, "wrong")
        }
        refused => {
            state.limiter.succeeded(attempt);
            refusal(refused, log)
        }
    }
}

/// What asking the helper gave.
enum Asked {
    Done(AuthOutcome),
    /// Every helper slot is taken.
    Busy,
    Down(crate::helper::HelperError),
}

/// Asks the helper, holding one of its few slots; malformed input never
/// reaches it.
async fn ask(state: &AppState, req: &LoginRequest) -> Asked {
    if !well_formed(&req.user, &req.password) {
        return Asked::Done(AuthOutcome::Wrong);
    }
    let Ok(_slot) = state.helper_slots.try_acquire() else { return Asked::Busy };
    match state.helper.authenticate(&req.user, &req.password).await {
        Ok(outcome) => Asked::Done(outcome),
        Err(e) => Asked::Down(e),
    }
}

/// The answers that do not count as failures: expired, busy, unavailable.
fn refusal(asked: Asked, log: impl Fn(&str)) -> Response {
    match asked {
        Asked::Done(AuthOutcome::Expired) => {
            log("sign-in refused: password must be changed");
            error(StatusCode::FORBIDDEN, "expired")
        }
        Asked::Busy => {
            log("sign-in refused: helper busy");
            too_many(1)
        }
        Asked::Down(e) => {
            log(&e.to_string());
            error(StatusCode::SERVICE_UNAVAILABLE, "unavailable")
        }
        Asked::Done(_) => unreachable!("successes and failures are answered by login"),
    }
}

fn too_many(wait: u64) -> Response {
    let mut res = error(StatusCode::TOO_MANY_REQUESTS, "rate");
    res.headers_mut().insert(header::RETRY_AFTER, wait.into());
    res
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
