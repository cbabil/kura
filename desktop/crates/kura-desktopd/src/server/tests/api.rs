use axum::http::header;

use super::*;

const PREFS: &str = r#"{"theme":"light","dock":["activity"],"windows":{"activity":{"x":1,"y":2,"w":640,"h":480}}}"#;

#[tokio::test]
async fn system_reports_the_device() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let (res, body) = app.send(request("GET", "/api/system", Some(&cookie), None)).await;
    assert_eq!(res.status(), 200);
    let v = json(&body);
    assert_eq!(
        (v["hostname"].as_str(), v["os"].as_str(), v["cores"].as_u64()),
        (Some("kura-nuc"), Some("Kura 0.6.0"), Some(2))
    );
    for key in ["kernel", "arch", "memTotal", "uptime"] {
        assert!(v.get(key).is_some(), "{key}");
    }
    std::fs::remove_file(app.fixture.dir.path().join("proc/uptime")).unwrap();
    let (res, body) = app.send(request("GET", "/api/system", Some(&cookie), None)).await;
    assert_eq!((res.status().as_u16(), json(&body)["error"].as_str()), (500, Some("internal")));
}

#[tokio::test]
async fn prefs_round_trip_per_user() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    assert_eq!(app.send(request("GET", "/api/prefs", Some(&cookie), None)).await.0.status(), 404);
    assert_eq!(app.send(request("PUT", "/api/prefs", Some(&cookie), Some(PREFS))).await.0.status(), 204);
    let (res, body) = app.send(request("GET", "/api/prefs", Some(&cookie), None)).await;
    assert_eq!(res.status(), 200);
    let parse = |s: &str| kura_desktop_core::prefs::Prefs::parse(s.as_bytes()).unwrap();
    assert_eq!(parse(&body), parse(PREFS));
    let root = app.sign_in("root").await;
    assert_eq!(app.send(request("GET", "/api/prefs", Some(&root), None)).await.0.status(), 404);
}

#[tokio::test]
async fn bad_prefs_are_refused() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let huge = format!(r#"{{"theme":"dark","dock":["{}"],"windows":{{}}}}"#, "a".repeat(70_000));
    let cases = [(r#"{"theme":"pink","dock":[],"windows":{}}"#.to_owned(), 400), (huge, 413)];
    for (body, status) in cases {
        let (res, _) = app.send(request("PUT", "/api/prefs", Some(&cookie), Some(&body))).await;
        assert_eq!(res.status(), status);
    }
}

#[tokio::test]
async fn prefs_storage_failures_are_500() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let dir = app.state_dir.path().join("prefs");
    std::fs::write(&dir, b"not a directory").unwrap();
    assert_eq!(app.send(request("PUT", "/api/prefs", Some(&cookie), Some(PREFS))).await.0.status(), 500);
    std::fs::remove_file(&dir).unwrap();
    std::fs::create_dir_all(dir.join("1000.json")).unwrap();
    assert_eq!(app.send(request("GET", "/api/prefs", Some(&cookie), None)).await.0.status(), 500);
}

#[tokio::test]
async fn every_response_carries_security_headers() {
    let app = TestApp::with(|s| s.assets = &[("/index.html", b"<html>")]);
    for path in ["/", "/api/session", "/api/nothing"] {
        let (res, _) = app.send(request("GET", path, None, None)).await;
        let h = res.headers();
        assert!(h[header::CONTENT_SECURITY_POLICY].to_str().unwrap().contains("frame-ancestors 'none'"));
        assert_eq!(h[header::X_CONTENT_TYPE_OPTIONS], "nosniff");
        assert_eq!(h[header::X_FRAME_OPTIONS], "DENY");
        assert_eq!(h[header::REFERRER_POLICY], "no-referrer");
        assert_eq!(h[header::CACHE_CONTROL] == "no-store", path.starts_with("/api/"), "{path}");
    }
    let (res, body) = app.send(request("GET", "/api/nothing", None, None)).await;
    assert_eq!((res.status().as_u16(), json(&body)["error"].as_str()), (404, Some("not_found")));
    let (res, body) = app.send(request("GET", "/apps/activity", None, None)).await;
    assert_eq!((res.status().as_u16(), body.as_str()), (200, "<html>"));
}
