use super::*;

async fn journal(app: &TestApp, cookie: &str, query: &str) -> (u16, serde_json::Value) {
    let (res, body) = app.send(request("GET", &format!("/api/journal{query}"), Some(cookie), None)).await;
    (res.status().as_u16(), json(&body))
}

#[tokio::test]
async fn administrators_read_and_filter_the_journal() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let (code, page) = journal(&app, &cookie, "").await;
    assert_eq!(
        (code, page["entries"].as_array().map(Vec::len), page["cursor"].as_str()),
        (200, Some(8), Some("s=dev;i=8"))
    );
    let first = &page["entries"][0];
    assert_eq!(
        (first["unit"].as_str(), first["ident"].as_str(), first["priority"].as_u64(), first["pid"].as_u64()),
        (Some("kura-desktopd.service"), Some("kura-desktopd"), Some(6), Some(601))
    );
    assert!(first["t"].as_i64().unwrap() < page["entries"][7]["t"].as_i64().unwrap(), "oldest first");

    let count = |page: &serde_json::Value| page["entries"].as_array().map(Vec::len);
    assert_eq!(count(&journal(&app, &cookie, "?unit=ssh.service").await.1), Some(2));
    assert_eq!(count(&journal(&app, &cookie, "?priority=4").await.1), Some(2));
    assert_eq!(count(&journal(&app, &cookie, "?unit=ssh.service&priority=3").await.1), Some(1));
    assert_eq!(count(&journal(&app, &cookie, "?lines=3").await.1), Some(3));
    let (_, newer) = journal(&app, &cookie, "?after=s%3Ddev%3Bi%3D6").await;
    assert_eq!((count(&newer), newer["cursor"].as_str()), (Some(2), Some("s=dev;i=8")));
    let (_, none) = journal(&app, &cookie, "?after=s%3Ddev%3Bi%3D8").await;
    assert_eq!((count(&none), none["cursor"].is_null()), (Some(0), true));
}

#[tokio::test]
async fn the_journal_refuses_others_and_bad_queries() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let cases = [
        (guest.as_str(), "", 403, "admin"),
        (admin.as_str(), "?lines=0", 400, "bad_request"),
        (admin.as_str(), "?lines=5000", 400, "bad_request"),
        (admin.as_str(), "?unit=--file%3D%2Fetc%2Fshadow", 400, "bad_request"),
        (admin.as_str(), "?priority=8", 400, "bad_request"),
        (admin.as_str(), "?after=--since", 400, "bad_request"),
        ("__Host-kura=forged", "", 401, "signed_out"),
    ];
    for (cookie, query, code, error) in cases {
        let (got, body) = journal(&app, cookie, query).await;
        assert_eq!((got, body["error"].as_str()), (code, Some(error)), "{query}");
    }
    let (res, _) = app.send(request("GET", "/api/journal?lines=many", Some(&admin), None)).await;
    assert_eq!(res.status(), 400);
}
