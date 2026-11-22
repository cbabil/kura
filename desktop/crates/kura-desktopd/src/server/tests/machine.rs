use super::*;

#[tokio::test]
async fn everyone_sees_the_update_and_administrators_install_it() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let get = |cookie: &str| request("GET", "/api/updates", Some(cookie), None);
    let post = |cookie: &str, what: &str| request("POST", &format!("/api/updates/{what}"), Some(cookie), None);

    let (code, seen) = status(&app, get(&guest)).await;
    assert_eq!(
        (code, seen["available"].as_str(), seen["restartRequired"].as_bool()),
        (200, Some("0.6.2"), Some(false))
    );
    assert!(seen["job"].is_null());
    assert_eq!(seen["current"].as_str(), Some("0.6.1"));
    assert_eq!(status(&app, get("__Host-kura=forged")).await.0, 401);

    let (code, body) = status(&app, post(&guest, "install")).await;
    assert_eq!((code, body["error"].as_str()), (403, Some("admin")));
    assert_eq!(status(&app, post(&admin, "downgrade")).await.0, 404);
    let mut forged = post(&admin, "install");
    forged.headers_mut().remove("x-kura-request");
    assert_eq!(status(&app, forged).await.0, 403, "the CSRF rule covers updates");

    assert_eq!(status(&app, post(&admin, "check")).await.0, 204);
    assert_eq!(status(&app, get(&admin)).await.1["available"].as_str(), Some("0.6.2"));
    assert_eq!(status(&app, post(&admin, "install")).await.0, 204);
    let (_, done) = status(&app, get(&admin)).await;
    assert_eq!((done["available"].is_null(), done["job"]["state"].as_str()), (true, Some("done")));
    assert!(done["job"]["output"][1].as_str().unwrap().contains("Setting up kura"));
    assert_eq!(
        status(&app, get(&guest)).await.1["job"]["output"].as_array().map(Vec::len),
        Some(0),
        "no output for others"
    );
}

#[tokio::test]
async fn only_administrators_restart_or_shut_down() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let post = |cookie: Option<&str>, how: &str| request("POST", &format!("/api/power/{how}"), cookie, None);
    for how in ["restart", "shutdown"] {
        let (code, body) = status(&app, post(Some(&guest), how)).await;
        assert_eq!((code, body["error"].as_str()), (403, Some("admin")), "{how}");
        assert_eq!(status(&app, post(Some(&admin), how)).await.0, 204, "{how}");
    }
    assert_eq!(status(&app, post(Some(&admin), "hibernate")).await.0, 404);
    assert!(status(&app, post(Some(&admin), "restart")).await.1.is_null(), "204 has no body");
    assert_eq!(status(&app, post(None, "restart")).await.0, 401);
    let mut forged = post(Some(&admin), "shutdown");
    forged.headers_mut().remove("x-kura-request");
    assert_eq!(status(&app, forged).await.0, 403);
    assert_eq!(status(&app, request("GET", "/api/power/restart", Some(&admin), None)).await.0, 405);
}
