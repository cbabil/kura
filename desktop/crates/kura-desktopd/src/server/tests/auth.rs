use axum::http::header;
use kura_desktop_core::ratelimit::MAX_FAILURES;

use super::*;
use crate::helper::DEV_PASSWORD;

#[tokio::test]
async fn sign_in_sets_a_strict_cookie_and_opens_a_session() {
    let app = TestApp::new();
    let (res, body) = app.send(login("kura", DEV_PASSWORD)).await;
    assert_eq!(res.status(), 200);
    assert_eq!(json(&body)["user"], serde_json::json!({ "name": "kura", "uid": 1000, "admin": true }));
    let cookie = res.headers()[header::SET_COOKIE].to_str().unwrap();
    for attr in ["__Host-kura=", "Path=/", "HttpOnly", "Secure", "SameSite=Strict"] {
        assert!(cookie.contains(attr), "{cookie}");
    }
    let pair = cookie.split(';').next().unwrap();
    let (res, body) = app.send(request("GET", "/api/session", Some(pair), None)).await;
    assert_eq!(res.status(), 200);
    assert_eq!(json(&body)["user"]["name"], "kura");
}

#[tokio::test]
async fn refusals_map_to_the_interface_status_codes() {
    let long = "x".repeat(600);
    let cases = [
        (login("kura", "nope"), 401, "wrong"),
        (login("expired", DEV_PASSWORD), 403, "expired"),
        (login("Not Valid", DEV_PASSWORD), 401, "wrong"),
        (login("kura", &long), 401, "wrong"),
        (login("down", DEV_PASSWORD), 503, "unavailable"),
        (login("ghost", DEV_PASSWORD), 401, "wrong"),
        (request("POST", "/api/login", None, Some("{not json")), 400, "bad_request"),
    ];
    for (req, status, code) in cases {
        let app = TestApp::new();
        let (res, body) = app.send(req).await;
        assert_eq!((res.status().as_u16(), json(&body)["error"].as_str().unwrap()), (status, code));
        assert!(res.headers().get(header::SET_COOKIE).is_none());
    }
}

#[tokio::test]
async fn a_dev_fallback_uid_covers_users_without_an_account() {
    let app = TestApp::with(|s| s.fallback_uid = Some(1234));
    let (res, body) = app.send(login("ghost", DEV_PASSWORD)).await;
    assert_eq!(res.status(), 200);
    assert_eq!(json(&body)["user"]["uid"], 1234);
}

#[tokio::test]
async fn too_many_failures_give_429_with_retry_after() {
    let app = TestApp::new();
    for _ in 0..MAX_FAILURES {
        assert_eq!(app.send(login("kura", "nope")).await.0.status(), 401);
    }
    let (res, body) = app.send(login("kura", DEV_PASSWORD)).await;
    assert_eq!(res.status(), 429);
    assert_eq!(json(&body)["error"], "rate");
    let retry: u64 = res.headers()[header::RETRY_AFTER].to_str().unwrap().parse().unwrap();
    assert!((1..=60).contains(&retry));
}

#[tokio::test]
async fn successes_and_expired_passwords_do_not_count() {
    let app = TestApp::new();
    for _ in 0..MAX_FAILURES + 1 {
        app.sign_in("kura").await;
        assert_eq!(app.send(login("expired", DEV_PASSWORD)).await.0.status(), 403);
    }
}

#[tokio::test]
async fn sign_out_ends_the_session_and_clears_the_cookie() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let (res, _) = app.send(request("POST", "/api/logout", Some(&cookie), None)).await;
    assert_eq!(res.status(), 204);
    assert!(res.headers()[header::SET_COOKIE].to_str().unwrap().contains("Max-Age=0"));
    assert_eq!(app.send(request("GET", "/api/session", Some(&cookie), None)).await.0.status(), 401);
    assert_eq!(app.send(request("POST", "/api/logout", None, None)).await.0.status(), 204);
}

#[tokio::test]
async fn changes_need_the_kura_header_and_this_origin() {
    let app = TestApp::new();
    let strip = |name: &str, value: Option<&'static str>| {
        let mut req = login("kura", DEV_PASSWORD);
        req.headers_mut().remove(name);
        if let Some(v) = value {
            req.headers_mut().insert(header::HeaderName::from_bytes(name.as_bytes()).unwrap(), v.parse().unwrap());
        }
        req
    };
    let cases = [
        strip("x-kura-request", None),
        strip("x-kura-request", Some("0")),
        strip("origin", None),
        strip("origin", Some("https://evil.example")),
        strip("origin", Some("http://kura.local")),
    ];
    for req in cases {
        let (res, body) = app.send(req).await;
        assert_eq!(res.status(), 403);
        assert_eq!(json(&body)["error"], "forbidden");
    }
    let put = request("PUT", "/api/prefs", None, Some("{}"));
    let (mut parts, body) = put.into_parts();
    parts.headers.remove("x-kura-request");
    assert_eq!(app.send(Request::from_parts(parts, body)).await.0.status(), 403);
}

#[tokio::test]
async fn signed_out_requests_get_401() {
    let app = TestApp::new();
    for path in ["/api/session", "/api/system", "/api/prefs"] {
        for cookie in [None, Some("__Host-kura=forged")] {
            let (res, body) = app.send(request("GET", path, cookie, None)).await;
            assert_eq!(res.status(), 401, "{path}");
            assert_eq!(json(&body)["error"], "signed_out");
        }
    }
    assert_eq!(app.send(request("PUT", "/api/prefs", None, Some("{}"))).await.0.status(), 401);
}
