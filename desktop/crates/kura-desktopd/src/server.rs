//! The HTTP routes of `desktop/web/src/api/client.ts`, with the CSRF and
//! session guards and the security headers every response carries.

mod api;
mod auth;
mod catalog;
mod containers;
mod files;
pub mod guard;
mod journal;
mod machine;
mod settings;
mod stats;
mod terminal;

use std::path::Path;
use std::sync::Arc;

use axum::Router;
use axum::extract::{DefaultBodyLimit, Request, State};
use axum::http::{HeaderValue, StatusCode, Uri, header};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{any, get, post};
use kura_desktop_core::prefs::PrefsStore;
use kura_desktop_core::ratelimit::RateLimiter;
use kura_desktop_core::root::SysRoot;
use kura_desktop_core::session::SessionStore;
use kura_desktop_core::stats::sampler::StatsHub;

use crate::assets::Files;
use crate::helper::Helper;

/// The largest sign-in body accepted.
const MAX_LOGIN_BYTES: usize = 4096;

/// The Content-Security-Policy: everything from this origin only. Inline
/// styles are allowed because MUI (emotion) injects them.
const CSP: &str = "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; \
connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'";

/// Everything the handlers share.
pub struct AppState {
    pub sessions: SessionStore,
    pub limiter: RateLimiter,
    pub helper: Arc<dyn Helper>,
    pub prefs: PrefsStore,
    pub hub: Arc<StatsHub>,
    pub root: SysRoot,
    /// "https", or "http" in a dev-auth build run with `--http`.
    pub scheme: &'static str,
    pub assets: Files,
    /// The uid for a user missing from `/etc/passwd` (development only);
    /// `None` refuses such a sign-in.
    pub fallback_uid: Option<u32>,
    /// Password checks in flight at most; more are refused with 429.
    pub helper_slots: tokio::sync::Semaphore,
    /// How long a wrong password waits before its answer.
    pub fail_delay: std::time::Duration,
    /// Terminals open at most, over all users; more are refused with 429.
    pub terminal_slots: Arc<tokio::sync::Semaphore>,
    /// The file agents of the sessions that use Files.
    pub files: crate::files::Links,
}

/// Password checks that may wait on the helper at once.
pub const HELPER_SLOTS: usize = 4;
/// The wait after a wrong password (PAM's own delay is turned off).
pub const FAIL_DELAY: std::time::Duration = std::time::Duration::from_secs(2);
/// Log lines or journal entries sent when the interface names no number.
pub const DEFAULT_LINES: u32 = 200;
/// Sessions one user may have at once (one per signed-in browser); the
/// oldest goes first, so one user cannot sign the others out by signing in.
pub const MAX_SESSIONS_PER_USER: usize = 8;
/// Terminals that may be open at once (the helper also counts per user).
pub const MAX_TERMINALS: usize = 16;

impl AppState {
    /// State with empty sessions and limits, preferences under `state_dir`.
    pub fn new(helper: Arc<dyn Helper>, hub: Arc<StatsHub>, root: SysRoot, state_dir: &Path) -> Self {
        Self {
            sessions: SessionStore::new(),
            limiter: RateLimiter::new(),
            helper,
            prefs: PrefsStore::new(state_dir.join("prefs")),
            hub,
            root,
            scheme: "https",
            assets: crate::assets::ASSETS,
            fallback_uid: None,
            helper_slots: tokio::sync::Semaphore::new(HELPER_SLOTS),
            fail_delay: FAIL_DELAY,
            terminal_slots: Arc::new(tokio::sync::Semaphore::new(MAX_TERMINALS)),
            files: crate::files::Links::default(),
        }
    }
}

/// Builds the application.
pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/api/session", get(auth::session))
        .route("/api/login", post(auth::login).layer(DefaultBodyLimit::max(MAX_LOGIN_BYTES)))
        .route("/api/logout", post(auth::logout))
        .route("/api/system", get(api::system))
        // Prefs::parse owns the size limit, so an oversized body gets the JSON 413.
        .route("/api/prefs", get(api::get_prefs).put(api::put_prefs))
        .route("/api/stats", get(stats::stats))
        .route("/api/terminal", get(terminal::terminal))
        .route("/api/containers", get(containers::list))
        .route("/api/containers/{id}/logs", get(containers::logs))
        .route("/api/containers/{id}/{action}", post(containers::act))
        .route("/api/journal", get(journal::read))
        .route("/api/updates", get(machine::status))
        .route("/api/updates/{what}", post(machine::update))
        .route("/api/power/{how}", post(machine::power))
        .route(
            "/api/settings",
            get(settings::read).post(settings::change).layer(DefaultBodyLimit::max(settings::MAX_BYTES)),
        )
        .route("/api/password", post(settings::password).layer(DefaultBodyLimit::max(settings::MAX_BYTES)))
        .route(
            "/api/catalog",
            get(catalog::read).post(catalog::change).layer(DefaultBodyLimit::max(catalog::MAX_BYTES)),
        )
        .route("/api/files", get(files::list).post(files::change).layer(DefaultBodyLimit::max(files::MAX_BYTES)))
        .route("/api/files/trash", get(files::trash))
        // An upload is as long as the file: the agent takes it in pieces.
        .route("/api/files/content", get(files::download).put(files::upload).layer(DefaultBodyLimit::disable()))
        .route("/api/{*rest}", any(|| async { guard::error(StatusCode::NOT_FOUND, "not_found") }))
        .fallback(assets)
        .layer(middleware::from_fn_with_state(state.clone(), guard::csrf))
        .layer(middleware::from_fn(security_headers))
        .with_state(state)
}

async fn assets(State(state): State<Arc<AppState>>, uri: Uri) -> Response {
    crate::assets::serve(state.assets, &uri)
}

async fn security_headers(req: Request, next: Next) -> Response {
    let api = req.uri().path().starts_with("/api/");
    let mut res = next.run(req).await;
    let h = res.headers_mut();
    h.insert(header::CONTENT_SECURITY_POLICY, HeaderValue::from_static(CSP));
    h.insert(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    h.insert(header::X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));
    h.insert(header::REFERRER_POLICY, HeaderValue::from_static("no-referrer"));
    // Another port of this host is the same site: it must not embed what is here.
    h.insert("cross-origin-resource-policy", HeaderValue::from_static("same-origin"));
    if api {
        h.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    }
    res.into_response()
}

#[cfg(test)]
mod tests;
