use super::*;

fn change(cookie: &str, body: &str) -> Request<Body> {
    request("POST", "/api/catalog", Some(cookie), Some(body))
}

async fn app(app: &TestApp, cookie: &str, id: &str) -> serde_json::Value {
    let (code, seen) = status(app, request("GET", "/api/catalog", Some(cookie), None)).await;
    assert_eq!(code, 200, "{seen}");
    seen["apps"].as_array().unwrap().iter().find(|a| a["id"] == id).cloned().unwrap_or_default()
}

#[tokio::test]
async fn administrators_install_update_and_remove_what_kura_ships() {
    let test = TestApp::with_guests();
    let (admin, guest) = (test.sign_in("kura").await, test.sign_in("guest").await);
    let (_, seen) = status(&test, request("GET", "/api/catalog", Some(&admin), None)).await;
    let names: Vec<&str> = seen["apps"].as_array().unwrap().iter().map(|a| a["name"].as_str().unwrap()).collect();
    assert_eq!(names, ["AdGuard Home", "Gitea", "Home Assistant", "Jellyfin", "Syncthing", "Uptime Kuma"]);
    assert!(seen["job"].is_null());
    let gitea = app(&test, &admin, "gitea").await;
    assert_eq!((gitea["installed"]["version"].as_str(), gitea["version"].as_str()), (Some("1.22.0"), Some("1.23.1")));

    assert_eq!(status(&test, change(&admin, r#"{"what":"install","id":"jellyfin","port":8096}"#)).await.0, 204);
    assert_eq!(app(&test, &admin, "jellyfin").await["installed"]["port"], 8096);
    assert_eq!(status(&test, change(&admin, r#"{"what":"update","id":"gitea"}"#)).await.0, 204);
    assert_eq!(app(&test, &admin, "gitea").await["installed"]["version"], "1.23.1");
    assert_eq!(status(&test, change(&admin, r#"{"what":"remove","id":"gitea","data":false}"#)).await.0, 204);
    assert!(app(&test, &admin, "gitea").await["installed"].is_null());
    let (_, after) = status(&test, request("GET", "/api/catalog", Some(&admin), None)).await;
    assert_eq!(
        (after["job"]["state"].as_str(), after["job"]["output"][0].as_str()),
        (Some("done"), Some("kura-apps remove gitea"))
    );

    assert_eq!(status(&test, request("GET", "/api/catalog", Some(&guest), None)).await.1["error"], "admin");
    assert_eq!(status(&test, change(&guest, r#"{"what":"install","id":"syncthing","port":8384}"#)).await.0, 403);
    assert_eq!(status(&test, request("GET", "/api/catalog", None, None)).await.0, 401);
}

#[tokio::test]
async fn only_the_catalog_and_only_a_port_and_only_from_the_desktop() {
    let test = TestApp::new();
    let admin = test.sign_in("kura").await;
    let refused = [
        r#"{"what":"install","id":"nextcloud","port":8080}"#,
        r#"{"what":"install","id":"jellyfin","port":80}"#,
        r#"{"what":"install","id":"jellyfin","port":3003}"#,
        r#"{"what":"install","id":"gitea","port":3999}"#,
        r#"{"what":"install","id":"jellyfin","port":8096,"image":"evil"}"#,
        r#"{"what":"update","id":"jellyfin"}"#,
        r#"{"what":"exec","id":"jellyfin"}"#,
        "not json",
    ];
    for body in refused {
        assert_eq!(
            status(&test, change(&admin, body)).await,
            (400, serde_json::json!({ "error": "bad_request" })),
            "{body}"
        );
    }
    let mut forged = change(&admin, r#"{"what":"install","id":"jellyfin","port":8096}"#);
    forged.headers_mut().remove("x-kura-request");
    assert_eq!(status(&test, forged).await.0, 403);
    assert!(app(&test, &admin, "jellyfin").await["installed"].is_null());
}
