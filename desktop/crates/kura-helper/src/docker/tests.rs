use axum::Router;
use axum::extract::{Path, RawQuery};
use axum::http::StatusCode;
use axum::routing::{get, post};

use super::*;

const LIST: &str =
    r#"[{"Id":"aaaaaaaaaaaa","Names":["/web"],"Image":"nginx","State":"running","Status":"Up","Created":1}]"#;

async fn act(Path((id, action)): Path<(String, String)>, RawQuery(q): RawQuery) -> StatusCode {
    let grace = q.as_deref() == Some("t=10");
    match (id.as_str(), action.as_str()) {
        ("aaaaaaaaaaaa", "start") if q.is_none() => StatusCode::NO_CONTENT,
        ("aaaaaaaaaaaa", "stop" | "restart") if grace => StatusCode::NO_CONTENT,
        ("bbbbbbbbbbbb", _) => StatusCode::NOT_MODIFIED,
        ("cccccccccccc", _) => StatusCode::NOT_FOUND,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

async fn logs(Path(id): Path<String>, RawQuery(q): RawQuery) -> (StatusCode, Vec<u8>) {
    if id != "aaaaaaaaaaaa" || q.as_deref() != Some("stdout=true&stderr=true&timestamps=true&tail=5") {
        return (StatusCode::NOT_FOUND, Vec::new());
    }
    let text = b"2026-11-21T10:00:00Z ready\n";
    let mut frame = vec![1, 0, 0, 0, 0, 0, 0, text.len() as u8];
    frame.extend(text);
    (StatusCode::OK, frame)
}

/// A stand-in for the Engine API on a socket in a temp folder.
fn engine(list: &'static str) -> (EngineDocker, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let socket = dir.path().join("docker.sock");
    let listener = tokio::net::UnixListener::bind(&socket).unwrap();
    let app = Router::new()
        .route(
            "/containers/json",
            get(move |RawQuery(q): RawQuery| async move {
                if q.as_deref() == Some("all=true") { (StatusCode::OK, list) } else { (StatusCode::BAD_REQUEST, "") }
            }),
        )
        .route("/containers/{id}/logs", get(logs))
        .route("/containers/{id}/{action}", post(act));
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (EngineDocker::new(socket), dir)
}

#[tokio::test]
async fn lists_acts_and_reads_logs() {
    let (docker, _dir) = engine(LIST);
    let list = docker.list().await.unwrap();
    assert_eq!((list.len(), list[0].name.as_str()), (1, "web"));
    for action in [ContainerAction::Start, ContainerAction::Stop, ContainerAction::Restart] {
        assert_eq!(docker.act("aaaaaaaaaaaa", action).await, Ok(()), "{action:?}");
    }
    assert_eq!(docker.act("bbbbbbbbbbbb", ContainerAction::Start).await, Ok(()), "already running");
    let lines = docker.logs("aaaaaaaaaaaa", 5).await.unwrap();
    assert_eq!((lines.len(), lines[0].text.as_str()), (1, "ready"));
}

#[tokio::test]
async fn failures_are_told_apart() {
    let (docker, _dir) = engine("{not a list");
    assert_eq!(docker.act("cccccccccccc", ContainerAction::Stop).await, Err(DockerError::NotFound));
    assert_eq!(docker.logs("cccccccccccc", 5).await, Err(DockerError::NotFound));
    let err = docker.act("dddddddddddd", ContainerAction::Stop).await.unwrap_err();
    assert!(err.to_string().contains("500"), "{err}");
    assert!(matches!(docker.list().await, Err(DockerError::Unavailable(_))), "bad JSON");
    let gone = EngineDocker::new("/nonexistent-kura/docker.sock");
    assert!(matches!(gone.list().await, Err(DockerError::Unavailable(_))));
    assert_eq!(EngineDocker::default().socket, PathBuf::from(SOCKET));
}
