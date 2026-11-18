//! Route tests through the whole router, with a fake helper and a fixture root.

mod api;
mod auth;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Request, Response, header};
use http_body_util::BodyExt;
use kura_desktop_core::auth::AuthOutcome;
use kura_desktop_core::stats::fixture::Fixture;
use kura_desktop_core::stats::sampler::StatsHub;
use tower::ServiceExt;

use super::{AppState, router};
use crate::helper::{AuthFuture, AuthHelper, DevHelper, HelperError};

pub(super) const HOST: &str = "kura.local";
pub(super) const ORIGIN: &str = "https://kura.local";

/// Answers like the helper would; "down" means the bus is gone.
struct Scripted;
impl AuthHelper for Scripted {
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> AuthFuture<'a> {
        let result = match user {
            "down" => Err(HelperError(zbus::Error::Failure("bus gone".into()))),
            "ghost" => Ok(AuthOutcome::Ok { admin: false }),
            _ => return DevHelper.authenticate(user, password),
        };
        Box::pin(async move { result })
    }
}

pub(super) struct TestApp {
    pub state: Arc<AppState>,
    pub fixture: Fixture,
    pub state_dir: tempfile::TempDir,
}

impl TestApp {
    pub fn new() -> Self {
        let fixture = Fixture::full();
        let state_dir = tempfile::tempdir().unwrap();
        let state = AppState::new(Arc::new(Scripted), StatsHub::new(), fixture.root(), state_dir.path());
        Self { state: Arc::new(state), fixture, state_dir }
    }

    pub fn with(f: impl FnOnce(&mut AppState)) -> Self {
        let mut app = Self::new();
        f(Arc::get_mut(&mut app.state).unwrap());
        app
    }

    pub fn router(&self) -> Router {
        router(self.state.clone()).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 2], 5000))))
    }

    pub async fn send(&self, req: Request<Body>) -> (Response<Body>, String) {
        let res = self.router().oneshot(req).await.unwrap();
        let (parts, body) = res.into_parts();
        let bytes = body.collect().await.unwrap().to_bytes();
        (Response::from_parts(parts, Body::empty()), String::from_utf8_lossy(&bytes).into_owned())
    }

    /// Signs in as `user` with the dev password and returns the cookie pair.
    pub async fn sign_in(&self, user: &str) -> String {
        let (res, _) = self.send(login(user, crate::helper::DEV_PASSWORD)).await;
        assert_eq!(res.status(), 200);
        let cookie = res.headers()[header::SET_COOKIE].to_str().unwrap();
        cookie.split(';').next().unwrap().to_owned()
    }
}

/// A request the interface would send: Host, and for changes Origin and
/// X-Kura-Request.
pub(super) fn request(method: &str, path: &str, cookie: Option<&str>, body: Option<&str>) -> Request<Body> {
    let mut b = Request::builder().method(method).uri(path).header(header::HOST, HOST);
    if method != "GET" {
        b = b.header(header::ORIGIN, ORIGIN).header("x-kura-request", "1");
    }
    if let Some(c) = cookie {
        b = b.header(header::COOKIE, c);
    }
    if body.is_some() {
        b = b.header(header::CONTENT_TYPE, "application/json");
    }
    b.body(body.map_or_else(Body::empty, |s| Body::from(s.to_owned()))).unwrap()
}

pub(super) fn login(user: &str, password: &str) -> Request<Body> {
    let body = serde_json::json!({ "user": user, "password": password }).to_string();
    request("POST", "/api/login", None, Some(&body))
}

pub(super) fn json(text: &str) -> serde_json::Value {
    serde_json::from_str(text).unwrap_or_else(|e| panic!("{e}: {text}"))
}
