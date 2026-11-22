use std::sync::atomic::Ordering;

use super::tests::{Rig, rig};
use crate::refusal::Refusal;

/// Two templates in the rig's catalog, one of them installed.
fn stocked() -> Rig {
    let rig = rig();
    for (id, name, port) in [("jellyfin", "Jellyfin", 8096), ("gitea", "Gitea", 3003)] {
        let folder = rig.dir.path().join(format!("usr/lib/kura/catalog/{id}"));
        std::fs::create_dir_all(&folder).unwrap();
        let facts = format!(
            r#"{{"id":"{id}","name":"{name}","version":"1.2.3","port":{port},"fixedPorts":[],"shared":[],"homepage":"https://example.org"}}"#
        );
        std::fs::write(folder.join("app.json"), facts).unwrap();
    }
    let app = rig.dir.path().join("srv/apps/gitea");
    std::fs::create_dir_all(&app).unwrap();
    std::fs::write(app.join(".env"), "KURA_PORT=3003\nKURA_VERSION=1.0.0\n").unwrap();
    rig
}

#[tokio::test]
async fn administrators_read_the_catalog_and_the_last_job() {
    let rig = stocked();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    let seen: serde_json::Value =
        serde_json::from_str(&rig.service.ask(&anna, "read-catalog", "").await.unwrap()).unwrap();
    assert_eq!(seen["apps"].as_array().unwrap().len(), 2);
    assert_eq!(
        (seen["apps"][0]["id"].as_str(), seen["apps"][0]["installed"]["version"].as_str()),
        (Some("gitea"), Some("1.0.0"))
    );
    assert!(seen["apps"][1]["installed"].is_null() && seen["job"].is_null());
    assert_eq!(rig.service.ask(&bob, "read-catalog", "").await, Err(Refusal::Admin));
    assert_eq!(rig.service.ask(&anna, "read-catalog", "{}").await, Err(Refusal::Invalid("arguments".into())));
}

#[tokio::test]
async fn an_app_is_installed_updated_and_removed_one_job_at_a_time() {
    let rig = stocked();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    let install = r#"{"what":"install","id":"jellyfin","port":8096}"#;
    assert_eq!(rig.service.ask(&bob, "change-app", install).await, Err(Refusal::Admin));
    assert_eq!(rig.service.ask(&anna, "change-app", install).await.unwrap(), "");
    assert_eq!(rig.apps.started.lock().unwrap().as_slice(), ["install jellyfin 8096"]);
    let seen: serde_json::Value =
        serde_json::from_str(&rig.service.ask(&anna, "read-catalog", "").await.unwrap()).unwrap();
    assert_eq!(
        (seen["job"]["state"].as_str(), seen["job"]["output"][0].as_str()),
        (Some("running"), Some("Pulling jellyfin"))
    );

    let update = r#"{"what":"update","id":"gitea"}"#;
    assert_eq!(rig.service.ask(&anna, "change-app", update).await, Err(Refusal::Busy), "one job at a time");
    rig.apps.finish.store(true, Ordering::Relaxed);
    rig.service.ask(&anna, "change-app", update).await.unwrap();
    rig.service.ask(&anna, "change-app", r#"{"what":"remove","id":"gitea","data":true}"#).await.unwrap();
    assert_eq!(rig.apps.started.lock().unwrap()[1..], ["update gitea", "remove gitea data"]);
}

#[tokio::test]
async fn jobs_take_turns_and_the_machine_stays_on_under_them() {
    let rig = stocked();
    let anna = rig.sign_in("anna").await;
    let install = r#"{"what":"install","id":"jellyfin","port":8096}"#;
    rig.service.ask(&anna, "change-app", install).await.unwrap();
    // An installation runs: no update beside it, no restart under it.
    assert_eq!(rig.service.ask(&anna, "start-update", r#"{"what":"install"}"#).await, Err(Refusal::Busy));
    assert_eq!(rig.service.ask(&anna, "power", r#"{"how":"restart"}"#).await, Err(Refusal::Busy));
    rig.apps.finish.store(true, Ordering::Relaxed);
    // An update runs (the fake machine's never ends): no installation beside it.
    rig.service.ask(&anna, "start-update", r#"{"what":"check"}"#).await.unwrap();
    assert_eq!(rig.service.ask(&anna, "change-app", r#"{"what":"update","id":"gitea"}"#).await, Err(Refusal::Busy));
}

#[tokio::test]
async fn only_what_the_catalog_holds_and_only_a_port() {
    let rig = stocked();
    let anna = rig.sign_in("anna").await;
    let refused = [
        r#"{"what":"install","id":"nextcloud","port":8080}"#,
        r#"{"what":"install","id":"../../etc","port":8080}"#,
        r#"{"what":"install","id":"gitea","port":3004}"#,
        r#"{"what":"install","id":"jellyfin","port":22}"#,
        r#"{"what":"install","id":"jellyfin","port":3003}"#,
        r#"{"what":"install","id":"jellyfin","port":8096,"image":"evil/image"}"#,
        r#"{"what":"update","id":"jellyfin"}"#,
        r#"{"what":"remove","id":"jellyfin","data":false}"#,
        r#"{"what":"run","id":"jellyfin"}"#,
        "",
    ];
    for args in refused {
        assert!(matches!(rig.service.ask(&anna, "change-app", args).await, Err(Refusal::Invalid(_))), "{args}");
    }
    assert!(rig.apps.started.lock().unwrap().is_empty());
    rig.apps.fail.store(true, Ordering::Relaxed);
    let install = r#"{"what":"install","id":"jellyfin","port":8096}"#;
    assert!(matches!(rig.service.ask(&anna, "change-app", install).await, Err(Refusal::Unavailable(_))));
}
