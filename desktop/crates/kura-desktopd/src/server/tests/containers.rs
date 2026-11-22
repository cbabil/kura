use super::*;

/// The sample container "immich-server" (see helper/dev/sample.rs).
const ID: &str = "aaaaaaaaaaaa";

#[tokio::test]
async fn everyone_signed_in_sees_the_containers() {
    let app = TestApp::with_guests();
    assert_eq!(status(&app, request("GET", "/api/containers", None, None)).await.0, 401);
    for user in ["kura", "guest"] {
        let cookie = app.sign_in(user).await;
        let (code, list) = status(&app, request("GET", "/api/containers", Some(&cookie), None)).await;
        assert_eq!((code, list.as_array().map(Vec::len)), (200, Some(7)), "{user}");
        assert_eq!(
            (
                list[0]["id"].as_str(),
                list[0]["name"].as_str(),
                list[0]["project"].as_str(),
                list[0]["ports"][0].as_u64()
            ),
            (Some(ID), Some("immich-server"), Some("immich"), Some(2283))
        );
    }
}

#[tokio::test]
async fn administrators_start_stop_and_restart() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let post = |cookie: &str, id: &str, action: &str| {
        request("POST", &format!("/api/containers/{id}/{action}"), Some(cookie), None)
    };
    let state_of = |list: &serde_json::Value| list[0]["state"].as_str().map(str::to_owned);

    assert_eq!(status(&app, post(&admin, ID, "stop")).await.0, 204);
    let (_, list) = status(&app, request("GET", "/api/containers", Some(&admin), None)).await;
    assert_eq!(state_of(&list).as_deref(), Some("exited"));
    for action in ["start", "restart"] {
        assert_eq!(status(&app, post(&admin, ID, action)).await.0, 204, "{action}");
    }
    let (_, list) = status(&app, request("GET", "/api/containers", Some(&admin), None)).await;
    assert_eq!(state_of(&list).as_deref(), Some("running"));

    let refusals = [
        (post(&guest, ID, "stop"), 403, "admin"),
        (post(&admin, ID, "kill"), 400, "bad_request"),
        (post(&admin, "immich-server", "stop"), 400, "bad_request"),
        (post(&admin, "000000000000", "stop"), 404, "not_found"),
        (request("POST", &format!("/api/containers/{ID}/stop"), None, None), 401, "signed_out"),
    ];
    for (req, code, error) in refusals {
        let (got, body) = status(&app, req).await;
        assert_eq!((got, body["error"].as_str()), (code, Some(error)));
    }
    let mut forged = post(&admin, ID, "stop");
    forged.headers_mut().remove("x-kura-request");
    assert_eq!(status(&app, forged).await.0, 403, "the CSRF rule covers container actions");
}

#[tokio::test]
async fn administrators_read_logs() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let logs = |cookie: &str, id: &str, query: &str| {
        request("GET", &format!("/api/containers/{id}/logs{query}"), Some(cookie), None)
    };
    let (code, lines) = status(&app, logs(&admin, ID, "?lines=5")).await;
    assert_eq!((code, lines.as_array().map(Vec::len)), (200, Some(5)));
    assert_eq!(
        (lines[4]["stream"].as_str(), lines[4]["text"].as_str()),
        (Some("stdout"), Some("immich-server: handled request 5"))
    );
    assert_eq!(status(&app, logs(&admin, ID, "")).await.1.as_array().map(Vec::len), Some(40), "200 lines by default");
    for (req, code, error) in [
        (logs(&guest, ID, ""), 403, "admin"),
        (logs(&admin, ID, "?lines=0"), 400, "bad_request"),
        (logs(&admin, ID, "?lines=1001"), 400, "bad_request"),
        (logs(&admin, "000000000000", ""), 404, "not_found"),
    ] {
        let (got, body) = status(&app, req).await;
        assert_eq!((got, body["error"].as_str()), (code, Some(error)));
    }
}

/// The helper's ticket can end on its own (the helper restarts, a week
/// passes); the session then ends too, so the interface asks to sign in again.
#[tokio::test]
async fn a_dead_ticket_ends_the_session() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let ticket = app.state.sessions.touch(cookie.split('=').nth(1).unwrap(), std::time::Instant::now()).unwrap().ticket;
    app.helper.sign_out(&ticket).await.unwrap();
    let (code, body) = status(&app, request("GET", "/api/containers", Some(&cookie), None)).await;
    assert_eq!((code, body["error"].as_str()), (401, Some("signed_out")));
    assert_eq!(status(&app, request("GET", "/api/session", Some(&cookie), None)).await.0, 401);
}

#[tokio::test]
async fn signing_out_ends_the_ticket() {
    let app = TestApp::new();
    let cookie = app.sign_in("kura").await;
    let ticket = app.state.sessions.touch(cookie.split('=').nth(1).unwrap(), std::time::Instant::now()).unwrap().ticket;
    let list = || crate::helper::ask(app.helper.as_ref(), &ticket, Action::ListContainers, &());
    assert!(list().await.is_ok());
    app.send(request("POST", "/api/logout", Some(&cookie), None)).await;
    assert_eq!(list().await, Err(HelperError::SignedOut));
}
