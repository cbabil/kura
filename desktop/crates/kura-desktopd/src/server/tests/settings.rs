use super::*;

fn change(cookie: &str, body: &str) -> Request<Body> {
    request("POST", "/api/settings", Some(cookie), Some(body))
}

async fn settings(app: &TestApp, cookie: &str) -> serde_json::Value {
    status(app, request("GET", "/api/settings", Some(cookie), None)).await.1
}

#[tokio::test]
async fn administrators_read_and_change_the_settings() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let seen = settings(&app, &admin).await;
    assert_eq!((seen["hostname"].as_str(), seen["time"]["zone"].as_str()), (Some("kura-dev"), Some("Europe/Paris")));
    assert_eq!(seen["network"]["devices"].as_array().map(Vec::len), Some(2));
    assert_eq!(seen["users"].as_array().map(Vec::len), Some(6));
    assert_eq!(status(&app, request("GET", "/api/settings", Some(&guest), None)).await.1["error"], "admin");

    let changes = [
        r#"{"what":"hostname","name":"attic"}"#,
        r#"{"what":"timezone","zone":"America/Chicago"}"#,
        r#"{"what":"ntp","on":false}"#,
        r#"{"what":"wifi-add","ssid":"Home","password":"correct horse","hidden":false}"#,
        r#"{"what":"ethernet-static","address":"192.168.1.60/24","gateway":"192.168.1.1","dns":["192.168.1.1"]}"#,
        r#"{"what":"user-add","name":"paul","password":"s3cret","admin":true}"#,
        r#"{"what":"user-admin","name":"guest","admin":true}"#,
        r#"{"what":"user-remove","name":"noshell"}"#,
    ];
    for body in changes {
        assert_eq!(status(&app, change(&admin, body)).await.0, 204, "{body}");
    }
    let seen = settings(&app, &admin).await;
    assert_eq!(
        (seen["hostname"].as_str(), seen["time"]["zone"].as_str(), seen["time"]["ntp"].as_bool()),
        (Some("attic"), Some("America/Chicago"), Some(false))
    );
    assert_eq!((seen["network"]["wifi"][0].as_str(), seen["network"]["pending"].as_bool()), (Some("Home"), Some(true)));
    assert_eq!(
        (seen["network"]["ethernet"]["method"].as_str(), seen["network"]["ethernet"]["address"].as_str()),
        (Some("manual"), Some("192.168.1.60/24"))
    );
    let users: Vec<_> = seen["users"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| (u["name"].as_str().unwrap(), u["admin"].as_bool().unwrap()))
        .collect();
    assert!(
        users.contains(&("paul", true)) && users.contains(&("guest", true)) && !users.iter().any(|u| u.0 == "noshell"),
        "{users:?}"
    );
    assert_eq!(status(&app, change(&admin, r#"{"what":"network-confirm"}"#)).await.0, 204);
    assert_eq!(settings(&app, &admin).await["network"]["pending"].as_bool(), Some(false));
}

#[tokio::test]
async fn changes_are_refused_when_they_should_be() {
    let app = TestApp::with_guests();
    let (admin, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    let long = format!(r#"{{"what":"hostname","name":"{}"}}"#, "a".repeat(5000));
    let cases = [
        (change(&guest, r#"{"what":"hostname","name":"mine"}"#), 403, "admin"),
        (change(&admin, r#"{"what":"hostname","name":"a;reboot"}"#), 400, "bad_request"),
        (change(&admin, r#"{"what":"format-disk"}"#), 400, "bad_request"),
        (change(&admin, r#"{"what":"hostname","name":"a","extra":1}"#), 400, "bad_request"),
        (change(&admin, "not json"), 400, "bad_request"),
        (change(&admin, r#"{"what":"user-remove","name":"kura"}"#), 400, "bad_request"),
        (change("__Host-kura=forged", r#"{"what":"ntp","on":true}"#), 401, "signed_out"),
    ];
    for (req, code, error) in cases {
        let (got, body) = status(&app, req).await;
        assert_eq!((got, body["error"].as_str()), (code, Some(error)));
    }
    assert_eq!(app.send(change(&admin, &long)).await.0.status(), 413);
    let mut forged = change(&admin, r#"{"what":"ntp","on":true}"#);
    forged.headers_mut().remove("x-kura-request");
    assert_eq!(status(&app, forged).await.0, 403, "the CSRF rule covers settings");
    assert_eq!(settings(&app, &admin).await["hostname"].as_str(), Some("kura-dev"));
}

#[tokio::test]
async fn everyone_changes_their_own_password_with_the_current_one() {
    let app = TestApp::with_guests();
    let guest = app.sign_in("guest").await;
    let post = |body: &str| request("POST", "/api/password", Some(&guest), Some(body));
    assert_eq!(status(&app, post(r#"{"current":"kura","password":"new pass"}"#)).await.0, 204);
    let (code, body) = status(&app, post(r#"{"current":"wrong","password":"new pass"}"#)).await;
    assert_eq!((code, body["error"].as_str()), (400, Some("bad_request")));
    assert_eq!(status(&app, post(r#"{"current":"kura","password":""}"#)).await.0, 400);
    assert_eq!(status(&app, post(r#"{"current":"kura","password":"x","name":"kura"}"#)).await.0, 400);
    assert_eq!(status(&app, request("POST", "/api/password", None, Some("{}"))).await.0, 401);
}
