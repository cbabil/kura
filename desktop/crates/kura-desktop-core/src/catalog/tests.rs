use super::*;

fn fixture() -> (SysRoot, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let facts = |id: &str, name: &str, port: u16, fixed: &str| {
        let folder = dir.path().join(format!("usr/lib/kura/catalog/{id}"));
        std::fs::create_dir_all(&folder).unwrap();
        let json = format!(
            r#"{{"id":"{id}","name":"{name}","version":"1.2.3","port":{port},"fixedPorts":[{fixed}],"shared":[],"homepage":"https://example.org"}}"#
        );
        std::fs::write(folder.join("app.json"), json).unwrap();
    };
    facts("jellyfin", "Jellyfin", 8096, "");
    facts("adguard-home", "AdGuard Home", 3000, "53,5353");
    facts("gitea", "Gitea", 3003, "");
    // Not templates: a folder that is not its id, facts that are not JSON, a name that is no id.
    facts("other", "Other", 4000, "");
    std::fs::rename(dir.path().join("usr/lib/kura/catalog/other"), dir.path().join("usr/lib/kura/catalog/renamed"))
        .unwrap();
    std::fs::create_dir_all(dir.path().join("usr/lib/kura/catalog/broken")).unwrap();
    std::fs::write(dir.path().join("usr/lib/kura/catalog/broken/app.json"), "{").unwrap();
    std::fs::create_dir_all(dir.path().join("usr/lib/kura/catalog/Bad Name")).unwrap();
    let app = dir.path().join("srv/apps/gitea");
    std::fs::create_dir_all(&app).unwrap();
    std::fs::write(app.join(".env"), "KURA_PORT=3999\nKURA_DATA=/srv/apps/gitea/data\nKURA_VERSION=1.0.0\n").unwrap();
    (SysRoot::new(dir.path()), dir)
}

#[test]
fn reads_the_templates_and_what_is_installed() {
    let (root, _dir) = fixture();
    let apps = read_apps(&root);
    let seen: Vec<(&str, Option<u16>)> =
        apps.iter().map(|a| (a.template.id.as_str(), a.installed.as_ref().map(|i| i.port))).collect();
    assert_eq!(seen, [("adguard-home", None), ("gitea", Some(3999)), ("jellyfin", None)], "by name, bad ones left out");
    assert_eq!(apps[1].installed.as_ref().unwrap().version, "1.0.0");
    assert_eq!(apps[0].template.fixed_ports, [53, 5353]);
    let json = serde_json::to_value(&apps[1]).unwrap();
    assert_eq!(
        (json["id"].as_str(), json["fixedPorts"].is_array(), json["installed"]["port"].as_u64()),
        (Some("gitea"), true, Some(3999))
    );
    assert_eq!(read_apps(&SysRoot::new("/nonexistent")), [], "no catalog is an empty one");
}

#[test]
fn ids_are_plain_names() {
    for good in ["gitea", "home-assistant", "a1"] {
        assert!(valid_app_id(good), "{good}");
    }
    for bad in ["", "a", "Gitea", "1app", "-app", "a/b", "..", "a b", &"a".repeat(32)] {
        assert!(!valid_app_id(bad), "{bad:?}");
    }
}

#[test]
fn a_change_becomes_the_root_commands_arguments() {
    let (root, _dir) = fixture();
    let apps = read_apps(&root);
    let change = |json: &str| serde_json::from_str::<AppChange>(json).unwrap().command(&apps);
    assert_eq!(change(r#"{"what":"install","id":"jellyfin","port":8096}"#).unwrap(), ["install", "jellyfin", "8096"]);
    assert_eq!(change(r#"{"what":"update","id":"gitea"}"#).unwrap(), ["update", "gitea"]);
    assert_eq!(change(r#"{"what":"remove","id":"gitea","data":false}"#).unwrap(), ["remove", "gitea"]);
    assert_eq!(change(r#"{"what":"remove","id":"gitea","data":true}"#).unwrap(), ["remove", "gitea", "data"]);

    use InvalidAppChange as No;
    let refused = [
        (r#"{"what":"install","id":"nextcloud","port":8080}"#, No::Unknown),
        (r#"{"what":"install","id":"renamed","port":8080}"#, No::Unknown),
        (r#"{"what":"install","id":"gitea","port":3003}"#, No::Installed),
        (r#"{"what":"install","id":"jellyfin","port":80}"#, No::Port),
        (r#"{"what":"install","id":"jellyfin","port":3999}"#, No::Port),
        (r#"{"what":"install","id":"adguard-home","port":5353}"#, No::Port),
        (r#"{"what":"update","id":"jellyfin"}"#, No::NotInstalled),
        (r#"{"what":"remove","id":"jellyfin","data":true}"#, No::NotInstalled),
    ];
    for (json, why) in refused {
        assert_eq!(change(json), Err(why), "{json}");
    }
    for bad in [
        r#"{"what":"install","id":"jellyfin","port":70000}"#,
        r#"{"what":"install","id":"jellyfin","port":"8096; id"}"#,
        r#"{"what":"install","id":"jellyfin","port":8096,"image":"evil"}"#,
        r#"{"what":"start","id":"jellyfin"}"#,
        r#"{"what":"remove","id":"gitea"}"#,
    ] {
        assert!(serde_json::from_str::<AppChange>(bad).is_err(), "{bad}");
    }
    let update: AppChange = serde_json::from_str(r#"{"what":"update","id":"gitea"}"#).unwrap();
    assert_eq!((update.id(), update.name()), ("gitea", "update"));
}
