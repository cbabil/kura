use super::*;

const GOOD: &str = r#"{"theme":"dark","language":"fr","dock":["activity","files"],"windows":{"activity":{"x":10,"y":20.5,"w":800,"h":500}}}"#;

#[test]
fn parses_the_interface_shape() {
    let p = Prefs::parse(GOOD.as_bytes()).unwrap();
    assert_eq!(p.theme, Theme::Dark);
    assert_eq!(p.language, "fr");
    assert_eq!(p.dock, ["activity", "files"]);
    assert_eq!(p.windows["activity"].y, 20.5);
}

#[test]
fn refuses_bad_bodies() {
    let big = format!(r#"{{"theme":"dark","dock":[],"windows":{{}},"pad":"{}"}}"#, "x".repeat(MAX_PREFS_BYTES));
    let many: Vec<String> = (0..=MAX_ITEMS).map(|i| format!("\"a{i}\"")).collect();
    let many = format!(r#"{{"theme":"dark","dock":[{}],"windows":{{}}}}"#, many.join(","));
    let cases: Vec<(String, &str)> = vec![
        (big, "larger"),
        ("not json".into(), "shape"),
        (r#"{"theme":"blue","dock":[],"windows":{}}"#.into(), "shape"),
        (r#"{"theme":"dark","dock":[]}"#.into(), "shape"),
        (r#"{"theme":"dark","dock":[],"windows":{},"extra":1}"#.into(), "shape"),
        (r#"{"theme":"dark","dock":[""],"windows":{}}"#.into(), "app id"),
        (r#"{"theme":"dark","dock":["a/b"],"windows":{}}"#.into(), "app id"),
        (many, "too many"),
        (r#"{"theme":"dark","language":"French!","dock":[],"windows":{}}"#.into(), "language"),
        (r#"{"theme":"dark","language":"x","dock":[],"windows":{}}"#.into(), "language"),
        (r#"{"theme":"dark","dock":[],"windows":{"a":{"x":1e9,"y":0,"w":1,"h":1}}}"#.into(), "geometry"),
        (r#"{"theme":"dark","dock":[],"windows":{"a":{"x":0,"y":0,"w":-1,"h":1}}}"#.into(), "geometry"),
        (r#"{"theme":"dark","dock":[],"windows":{"a":{"x":0,"y":0,"w":1}}}"#.into(), "shape"),
    ];
    for (body, want) in cases {
        let err = Prefs::parse(body.as_bytes()).unwrap_err().to_string();
        assert!(err.contains(want), "{body:.60}: {err}");
    }
}

#[test]
fn store_round_trip_with_private_files() {
    let dir = tempfile::tempdir().unwrap();
    let store = PrefsStore::new(dir.path().join("prefs"));
    assert!(store.load(1000).unwrap().is_none());
    let p = Prefs::parse(GOOD.as_bytes()).unwrap();
    store.save(1000, &p).unwrap();
    assert_eq!(store.load(1000).unwrap(), Some(p));
    assert!(store.load(1001).unwrap().is_none());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(dir.path().join("prefs/1000.json")).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}

#[test]
fn a_corrupt_saved_file_reads_as_none() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("7.json"), b"{broken").unwrap();
    assert!(PrefsStore::new(dir.path()).load(7).unwrap().is_none());
}

#[test]
fn io_errors_are_reported() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir(dir.path().join("7.json")).unwrap();
    let store = PrefsStore::new(dir.path());
    assert!(matches!(store.load(7), Err(PrefsError::Io(_))));
    let file = dir.path().join("plain");
    std::fs::write(&file, b"").unwrap();
    let p = Prefs::parse(GOOD.as_bytes()).unwrap();
    assert!(PrefsStore::new(file).save(1, &p).is_err());
}

#[test]
fn languages() {
    let cases = [
        ("auto", true),
        ("fr", true),
        ("pt-BR", true),
        ("zh-Hant-TW", true),
        ("", false),
        ("FR", false),
        ("f", false),
        ("fr-", false),
        ("fr-x", false),
        ("frfr", false),
        ("en-verylongpart", false),
    ];
    for (lang, want) in cases {
        assert_eq!(valid_language(lang), want, "{lang}");
    }
}

#[test]
fn a_missing_language_means_auto() {
    let p = Prefs::parse(br#"{"theme":"system","dock":[],"windows":{}}"#).unwrap();
    assert_eq!(p.language, "auto");
}
