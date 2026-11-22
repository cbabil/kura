use super::tests::rig;
use crate::refusal::Refusal;

const PAUL: &str = r#"{"what":"user-add","name":"paul","password":"s3cret","admin":false}"#;

#[tokio::test]
async fn administrators_read_the_settings_and_passwords_are_never_in_them() {
    let rig = rig();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    std::fs::create_dir_all(rig.dir.path().join("etc/kura")).unwrap();
    std::fs::create_dir_all(rig.dir.path().join("var/lib/kura")).unwrap();
    let config = r#"{"hostname":"attic","networkConfig":{"wifi":{"networks":[{"ssid":"Home","psk":"wifi secret"}]}}}"#;
    std::fs::write(rig.dir.path().join("etc/kura/config.json"), config).unwrap();
    std::fs::write(rig.dir.path().join("var/lib/kura/storage-status"), "applied\n").unwrap();

    assert_eq!(rig.service.ask(&bob, "read-settings", "").await, Err(Refusal::Admin));
    let text = rig.service.ask(&anna, "read-settings", "").await.unwrap();
    let seen: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!((seen["hostname"].as_str(), seen["storage"].as_str()), (Some("attic"), Some("applied")));
    assert!(seen["screen"].is_null(), "an image without the local screen");
    let units = rig.dir.path().join("usr/lib/systemd/system");
    std::fs::create_dir_all(&units).unwrap();
    std::fs::write(units.join("kura-kiosk.service"), "").unwrap();
    let no_browser = rig.service.ask(&anna, "read-settings", "").await.unwrap();
    assert!(no_browser.contains(r#""screen":null"#), "the unit alone is every PC image");
    std::fs::create_dir_all(rig.dir.path().join("usr/bin")).unwrap();
    std::fs::write(rig.dir.path().join("usr/bin/cage"), "").unwrap();
    let again: serde_json::Value =
        serde_json::from_str(&rig.service.ask(&anna, "read-settings", "").await.unwrap()).unwrap();
    assert_eq!(again["screen"], false);
    rig.service.ask(&anna, "change-setting", r#"{"what":"screen","on":true}"#).await.unwrap();
    assert_eq!(rig.system.commands.lock().unwrap().last().map(String::as_str), Some("screen on"));
    assert_eq!(seen["network"]["wifi"], serde_json::json!(["Home"]));
    let device = &seen["network"]["devices"][0];
    assert_eq!((device["name"].as_str(), seen["network"]["pending"].as_bool()), (Some("enp1s0"), Some(false)));
    assert_eq!((seen["time"]["zone"].as_str(), seen["time"]["ntp"].as_bool()), (Some("Europe/Paris"), Some(true)));
    let users = seen["users"].as_array().unwrap();
    let users: Vec<_> = users.iter().map(|u| (u["name"].as_str().unwrap(), u["admin"].as_bool().unwrap())).collect();
    assert_eq!(users, [("anna", true), ("bob", false), ("old", false), ("carl", false)]);
    assert!(!text.contains("wifi secret"));
    std::fs::write(rig.dir.path().join("var/lib/kura/network-previous.json"), "{}").unwrap();
    assert!(rig.service.ask(&anna, "read-settings", "").await.unwrap().contains(r#""pending":true"#));
}

#[tokio::test]
async fn a_change_is_checked_then_run_with_its_secret_apart() {
    let rig = rig();
    let (anna, bob) = (rig.sign_in("anna").await, rig.sign_in("bob").await);
    let change = |ticket: &str, args: &'static str| {
        let ticket = ticket.to_owned();
        let service = rig.service.clone();
        async move { service.ask(&ticket, "change-setting", args).await }
    };
    assert_eq!(change(&bob, r#"{"what":"hostname","name":"attic"}"#).await, Err(Refusal::Admin));
    assert_eq!(change(&anna, r#"{"what":"hostname","name":"attic"}"#).await.unwrap(), "");
    assert_eq!(change(&anna, PAUL).await.unwrap(), "");
    assert_eq!(rig.system.commands.lock().unwrap().as_slice(), ["hostname attic", "user-add paul false"]);
    assert_eq!(rig.system.secrets.lock().unwrap().as_slice(), ["s3cret"]);

    for bad in [
        r#"{"what":"hostname","name":"a;reboot"}"#,
        r#"{"what":"format-disk"}"#,
        r#"{"what":"user-remove","name":"anna"}"#,
        r#"{"what":"user-password","name":"anna","password":"no current one"}"#,
        r#"{"what":"user-password","name":"bob","password":"a\nroot:x"}"#,
        "{}",
    ] {
        assert!(matches!(change(&anna, bad).await, Err(Refusal::Invalid(_))), "{bad}");
    }
    assert_eq!(rig.system.commands.lock().unwrap().len(), 2, "nothing invalid reached the root command");

    *rig.system.refuse.lock().unwrap() = Some("the last administrator stays one".into());
    let refused = change(&anna, r#"{"what":"user-admin","name":"anna","admin":false}"#).await;
    assert_eq!(refused, Err(Refusal::Unavailable("the last administrator stays one".into())));
}

#[tokio::test]
async fn anyone_changes_their_own_password_with_the_current_one() {
    let rig = rig();
    let bob = rig.sign_in("bob").await;
    let ask = |args: &'static str| rig.service.ask(&bob, "change-own-password", args);
    assert!(matches!(ask(r#"{"current":"nope","password":"new pass"}"#).await, Err(Refusal::Invalid(_))));
    assert!(matches!(ask(r#"{"current":"kura","password":""}"#).await, Err(Refusal::Invalid(_))));
    assert!(matches!(ask(r#"{"current":"kura","password":"x","name":"anna"}"#).await, Err(Refusal::Invalid(_))));
    assert!(rig.system.commands.lock().unwrap().is_empty());
    assert_eq!(ask(r#"{"current":"kura","password":"new pass"}"#).await.unwrap(), "");
    assert_eq!(rig.system.commands.lock().unwrap().as_slice(), ["user-password bob"], "only ever their own");
    assert_eq!(rig.system.secrets.lock().unwrap().as_slice(), ["new pass"]);
    assert!(rig.service.keep_alive(&bob).is_ok(), "still signed in");
}

#[tokio::test]
async fn a_changed_password_or_a_removal_ends_that_persons_other_sign_ins() {
    let rig = rig();
    let anna = rig.sign_in("anna").await;
    let (here, elsewhere) = (rig.sign_in("bob").await, rig.sign_in("bob").await);
    rig.service.ask(&here, "change-own-password", r#"{"current":"kura","password":"new pass"}"#).await.unwrap();
    assert!(rig.service.keep_alive(&here).is_ok(), "the browser that changed it stays");
    assert_eq!(rig.service.keep_alive(&elsewhere), Err(Refusal::SignedOut));

    let again = rig.sign_in("bob").await;
    rig.service
        .ask(&anna, "change-setting", r#"{"what":"user-password","name":"bob","password":"by anna"}"#)
        .await
        .unwrap();
    assert_eq!(rig.service.keep_alive(&here), Err(Refusal::SignedOut));
    assert_eq!(rig.service.keep_alive(&again), Err(Refusal::SignedOut));
    let last = rig.sign_in("bob").await;
    rig.service.ask(&anna, "change-setting", r#"{"what":"user-remove","name":"bob"}"#).await.unwrap();
    assert_eq!(rig.service.keep_alive(&last), Err(Refusal::SignedOut));
    assert!(rig.service.keep_alive(&anna).is_ok());
}

#[tokio::test]
async fn changes_run_one_at_a_time() {
    let rig = rig();
    let anna = rig.sign_in("anna").await;
    let off = |name: &'static str| {
        let (service, ticket) = (rig.service.clone(), anna.clone());
        async move {
            service
                .ask(&ticket, "change-setting", &format!(r#"{{"what":"user-admin","name":"{name}","admin":false}}"#))
                .await
        }
    };
    let (a, b) = tokio::join!(off("anna"), off("bob"));
    assert!(a.is_ok() && b.is_ok());
    assert_eq!(rig.system.most_at_once.load(std::sync::atomic::Ordering::Relaxed), 1);
}
