use axum::http::StatusCode;
use kura_desktop_core::files::CHUNK;

use super::*;

fn get(cookie: &str, path: &str) -> Request<Body> {
    request("GET", path, Some(cookie), None)
}

fn op(cookie: &str, body: &str) -> Request<Body> {
    request("POST", "/api/files", Some(cookie), Some(body))
}

fn put(cookie: &str, path: &str, bytes: Vec<u8>) -> Request<Body> {
    let (mut parts, _) = request("PUT", &format!("/api/files/content?path={path}"), Some(cookie), None).into_parts();
    parts.headers.insert(header::CONTENT_TYPE, "application/octet-stream".parse().unwrap());
    Request::from_parts(parts, Body::from(bytes))
}

async fn names(app: &TestApp, cookie: &str, path: &str) -> Vec<String> {
    let (code, listed) = status(app, get(cookie, &format!("/api/files?path={path}"))).await;
    assert_eq!(code, 200, "{listed}");
    let mut names: Vec<String> =
        listed["entries"].as_array().unwrap().iter().map(|e| e["name"].as_str().unwrap().to_owned()).collect();
    names.sort();
    names
}

async fn bytes_of(app: &TestApp, req: Request<Body>) -> (Response<Body>, Vec<u8>) {
    let res = app.router().oneshot(req).await.unwrap();
    let (parts, body) = res.into_parts();
    (Response::from_parts(parts, Body::empty()), body.collect().await.unwrap().to_bytes().to_vec())
}

#[tokio::test]
async fn a_person_sees_their_home_and_changes_it() {
    let app = TestApp::new();
    let kura = app.sign_in("kura").await;
    let (code, home) = status(&app, get(&kura, "/api/files")).await;
    assert_eq!(code, 200);
    assert_eq!((home["path"].as_str(), home["home"].as_str()), (Some("/home/kura"), Some("/home/kura")));
    assert_eq!(names(&app, &kura, "/home/kura").await, ["Documents", "Welcome.txt"]);
    let welcome = home["entries"].as_array().unwrap().iter().find(|e| e["name"] == "Welcome.txt").unwrap();
    assert_eq!((welcome["dir"].as_bool(), welcome["size"].as_u64()), (Some(false), Some(33)));

    let ops = [
        r#"{"op":"make-dir","path":"/home/kura/Photos"}"#,
        r#"{"op":"rename","from":"/home/kura/Welcome.txt","to":"/home/kura/Photos/Hello.txt"}"#,
        r#"{"op":"copy","from":"/home/kura/Photos","to":"/home/kura/Photos 2"}"#,
        r#"{"op":"delete","path":"/home/kura/Photos 2/Hello.txt"}"#,
    ];
    for body in ops {
        assert_eq!(status(&app, op(&kura, body)).await, (204, serde_json::Value::Null), "{body}");
    }
    assert_eq!(names(&app, &kura, "/home/kura").await, ["Documents", "Photos", "Photos 2"]);
    assert_eq!(names(&app, &kura, "/home/kura/Photos").await, ["Hello.txt"]);
    assert_eq!(names(&app, &kura, "/home/kura/Photos%202").await, Vec::<String>::new());
    assert_eq!(app.state.files.len(), 1, "one agent for the session");
}

#[tokio::test]
async fn refusals_have_their_own_answers() {
    let app = TestApp::new();
    let kura = app.sign_in("kura").await;
    let cases = [
        (get(&kura, "/api/files?path=/home/nobody"), 404, "not_found"),
        (get(&kura, "/api/files?path=/home/../etc"), 400, "bad_request"),
        (get(&kura, "/api/files?path=relative"), 400, "bad_request"),
        (op(&kura, r#"{"op":"make-dir","path":"/home/kura/Documents"}"#), 409, "exists"),
        (op(&kura, r#"{"op":"delete","path":"/home/kura/none"}"#), 404, "not_found"),
        (op(&kura, r#"{"op":"read","path":"/home/kura/Welcome.txt","offset":0}"#), 400, "bad_request"),
        (op(&kura, r#"{"op":"hello"}"#), 400, "bad_request"),
        (op(&kura, r#"{"op":"exec","path":"/bin/sh"}"#), 400, "bad_request"),
        (op(&kura, "not json"), 400, "bad_request"),
        (get(&kura, "/api/files/content?path=/home/kura/Documents"), 400, "bad_request"),
        (get(&kura, "/api/files/content?path=/home/kura/none"), 404, "not_found"),
        (get(&kura, "/api/files/content"), 400, "bad_request"),
        (put(&kura, "/home/kura/Welcome.txt", b"over".to_vec()), 409, "exists"),
        (request("GET", "/api/files", None, None), 401, "signed_out"),
        (request("GET", "/api/files/trash", None, None), 401, "signed_out"),
        (request("POST", "/api/files", None, Some(r#"{"op":"empty-trash"}"#)), 401, "signed_out"),
    ];
    for (req, code, error) in cases {
        let what = format!("{} {}", req.method(), req.uri());
        let (got, body) = status(&app, req).await;
        assert_eq!((got, body["error"].as_str()), (code, Some(error)), "{what}");
    }
    // A change from another site never reaches the agent.
    let mut forged = op(&kura, r#"{"op":"empty-trash"}"#);
    forged.headers_mut().remove("x-kura-request");
    assert_eq!(status(&app, forged).await.0, 403);
    let mut forged = put(&kura, "/home/kura/x", b"x".to_vec());
    forged.headers_mut().insert(header::ORIGIN, "https://evil.example".parse().unwrap());
    assert_eq!(status(&app, forged).await.0, 403);
}

#[tokio::test]
async fn files_go_up_and_come_down_whole() {
    let app = TestApp::new();
    let kura = app.sign_in("kura").await;
    let big: Vec<u8> = (0..2 * CHUNK + 4321).map(|i| (i % 253) as u8).collect();
    assert_eq!(status(&app, put(&kura, "/home/kura/Documents/big%20file.bin", big.clone())).await.0, 204);
    assert_eq!(status(&app, put(&kura, "/home/kura/Documents/empty", Vec::new())).await.0, 204);
    assert_eq!(status(&app, put(&kura, "/home/kura/Documents/exact", vec![7; CHUNK])).await.0, 204);
    assert_eq!(names(&app, &kura, "/home/kura/Documents").await, ["big file.bin", "empty", "exact"]);

    let (res, body) = bytes_of(&app, get(&kura, "/api/files/content?path=/home/kura/Documents/big%20file.bin")).await;
    assert_eq!(res.status(), StatusCode::OK);
    assert!(body == big, "the same bytes come back");
    let h = res.headers();
    assert_eq!(h[header::CONTENT_LENGTH], big.len().to_string().as_str());
    assert_eq!(h[header::CONTENT_TYPE], "application/octet-stream");
    assert_eq!(h[header::CONTENT_DISPOSITION], "attachment; filename*=UTF-8''big%20file.bin");
    assert_eq!(h[header::X_CONTENT_TYPE_OPTIONS], "nosniff");
    assert_eq!(bytes_of(&app, get(&kura, "/api/files/content?path=/home/kura/Documents/empty")).await.1, b"");
    assert_eq!(bytes_of(&app, get(&kura, "/api/files/content?path=/home/kura/Documents/exact")).await.1.len(), CHUNK);
}

#[tokio::test]
async fn only_plain_text_and_pictures_are_shown_in_the_page() {
    let app = TestApp::new();
    let kura = app.sign_in("kura").await;
    for name in ["a.png", "b.JPG", "c.txt", "d.html", "e.svg", "f"] {
        assert_eq!(status(&app, put(&kura, &format!("/home/kura/{name}"), b"<script>".to_vec())).await.0, 204);
    }
    let shown = [
        ("a.png", "image/png", "inline"),
        ("b.JPG", "image/jpeg", "inline"),
        ("c.txt", "text/plain; charset=utf-8", "inline"),
        // What a browser would run is only ever downloaded.
        ("d.html", "application/octet-stream", "attachment; filename*=UTF-8''d.html"),
        ("e.svg", "application/octet-stream", "attachment; filename*=UTF-8''e.svg"),
        ("f", "application/octet-stream", "attachment; filename*=UTF-8''f"),
    ];
    for (name, kind, disposition) in shown {
        let (res, _) = bytes_of(&app, get(&kura, &format!("/api/files/content?path=/home/kura/{name}&inline=1"))).await;
        assert_eq!(res.headers()[header::CONTENT_TYPE], kind, "{name}");
        assert_eq!(res.headers()[header::CONTENT_DISPOSITION], disposition, "{name}");
    }
    let (res, _) = bytes_of(&app, get(&kura, "/api/files/content?path=/home/kura/a.png")).await;
    assert_eq!(res.headers()[header::CONTENT_TYPE], "application/octet-stream", "a download unless asked inline");
}

#[tokio::test]
async fn the_trash_holds_what_was_removed_until_it_is_emptied() {
    let app = TestApp::new();
    let kura = app.sign_in("kura").await;
    assert_eq!(status(&app, get(&kura, "/api/files/trash")).await, (200, serde_json::json!({ "items": [] })));
    assert_eq!(status(&app, op(&kura, r#"{"op":"trash","path":"/home/kura/Welcome.txt"}"#)).await.0, 204);
    assert_eq!(names(&app, &kura, "/home/kura").await, [".local", "Documents"]);
    let (_, trash) = status(&app, get(&kura, "/api/files/trash")).await;
    let item = &trash["items"][0];
    assert_eq!((item["name"].as_str(), item["path"].as_str()), (Some("Welcome.txt"), Some("/home/kura/Welcome.txt")));
    assert!(item["deleted"].as_i64().unwrap() > 1_600_000_000);

    assert_eq!(status(&app, op(&kura, r#"{"op":"restore","name":"Welcome.txt"}"#)).await.0, 204);
    assert_eq!(status(&app, op(&kura, r#"{"op":"restore","name":"Welcome.txt"}"#)).await.1["error"], "not_found");
    assert_eq!(status(&app, op(&kura, r#"{"op":"trash","path":"/home/kura/Welcome.txt"}"#)).await.0, 204);
    assert_eq!(status(&app, op(&kura, r#"{"op":"empty-trash"}"#)).await.0, 204);
    assert_eq!(status(&app, get(&kura, "/api/files/trash")).await.1, serde_json::json!({ "items": [] }));
}

#[tokio::test]
async fn files_end_with_the_sign_in_and_are_for_people_with_a_shell() {
    let app = TestApp::with_guests();
    let (kura, anna) = (app.sign_in("kura").await, app.sign_in("anna").await);
    assert_eq!(status(&app, get(&anna, "/api/files")).await.0, 200);
    // An administrator gives anna a new password: her open browser loses its files at once.
    let change = r#"{"what":"user-password","name":"anna","password":"another one"}"#;
    assert_eq!(status(&app, request("POST", "/api/settings", Some(&kura), Some(change))).await.0, 204);
    assert_eq!(status(&app, get(&anna, "/api/files")).await, (401, serde_json::json!({ "error": "signed_out" })));
    assert_eq!(status(&app, get(&anna, "/api/session")).await.0, 401, "and her session with them");

    let noshell = app.sign_in("noshell").await;
    assert_eq!(status(&app, get(&noshell, "/api/files")).await, (403, serde_json::json!({ "error": "no_shell" })));
    let (res, _) = app.send(get(&kura, "/api/files")).await;
    assert_eq!(res.headers()["cross-origin-resource-policy"], "same-origin");
}

#[tokio::test]
async fn each_session_has_its_own_agent_which_goes_with_it() {
    let app = TestApp::with_guests();
    let (kura, guest) = (app.sign_in("kura").await, app.sign_in("guest").await);
    assert_eq!(status(&app, get(&guest, "/api/files")).await.1["path"], "/home/guest");
    assert_eq!(status(&app, get(&kura, "/api/files")).await.1["path"], "/home/kura");
    assert_eq!(app.state.files.len(), 2);
    // Many requests at once still make one agent.
    let many = (0..8).map(|_| status(&app, get(&kura, "/api/files")));
    assert!(futures_util::future::join_all(many).await.iter().all(|(code, _)| *code == 200));
    assert_eq!(app.state.files.len(), 2);
    assert_eq!(status(&app, request("POST", "/api/logout", Some(&kura), None)).await.0, 204);
    assert_eq!(app.state.files.len(), 1);
    assert_eq!(status(&app, get(&kura, "/api/files")).await.0, 401);
}
