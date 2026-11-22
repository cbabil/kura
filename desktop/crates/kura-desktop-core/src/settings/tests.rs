use super::*;

fn change(json: &str) -> Change {
    serde_json::from_str(json).unwrap_or_else(|e| panic!("{e}: {json}"))
}

fn args(json: &str) -> Vec<String> {
    change(json).command().unwrap().args
}

#[test]
fn each_change_becomes_its_command() {
    let cases = [
        (r#"{"what":"hostname","name":"attic-nas"}"#, "hostname attic-nas"),
        (r#"{"what":"timezone","zone":"Europe/Paris"}"#, "timezone Europe/Paris"),
        (r#"{"what":"ntp","on":false}"#, "ntp off"),
        (r#"{"what":"wifi-add","ssid":"Attic 5G","password":"correct horse","hidden":true}"#, "wifi-add|Attic 5G|true"),
        (r#"{"what":"wifi-remove","ssid":"Attic"}"#, "wifi-remove Attic"),
        (r#"{"what":"ethernet-auto"}"#, "ethernet auto"),
        (
            r#"{"what":"ethernet-static","address":"192.168.1.50/24","gateway":"192.168.1.1","dns":["192.168.1.1","9.9.9.9"]}"#,
            "ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1,9.9.9.9",
        ),
        (r#"{"what":"network-confirm"}"#, "network-confirm"),
        (r#"{"what":"user-add","name":"carl","password":"p w","admin":true}"#, "user-add carl true"),
        (r#"{"what":"user-remove","name":"carl"}"#, "user-remove carl"),
        (r#"{"what":"user-admin","name":"carl","admin":false}"#, "user-admin carl off"),
        (r#"{"what":"user-password","name":"carl","password":"x"}"#, "user-password carl"),
    ];
    for (json, want) in cases {
        let sep = if want.contains('|') { "|" } else { " " };
        assert_eq!(args(json).join(sep), want, "{json}");
    }
}

#[test]
fn a_password_travels_apart_and_stays_out_of_debug() {
    let add = change(r#"{"what":"user-add","name":"carl","password":"s3cret","admin":false}"#);
    let command = add.command().unwrap();
    assert_eq!(command.secret.as_deref().map(String::as_str), Some("s3cret"));
    assert!(!command.args.iter().any(|a| a.contains("s3cret")));
    assert_eq!(format!("{add:?}"), "Change(user-add)");
    assert!(change(r#"{"what":"ntp","on":true}"#).command().unwrap().secret.is_none());
    assert_eq!((add.user(), change(r#"{"what":"user-remove","name":"bob"}"#).user()), (None, Some("bob")));
}

#[test]
fn values_that_are_not_what_they_should_be_are_refused() {
    let long = "a".repeat(64);
    let bad = [
        r#"{"what":"hostname","name":""}"#.to_owned(),
        r#"{"what":"hostname","name":"Attic"}"#.to_owned(),
        r#"{"what":"hostname","name":"-attic"}"#.to_owned(),
        r#"{"what":"hostname","name":"a.b"}"#.to_owned(),
        r#"{"what":"hostname","name":"a;reboot"}"#.to_owned(),
        format!(r#"{{"what":"hostname","name":"{long}"}}"#),
        r#"{"what":"timezone","zone":"../../etc/passwd"}"#.to_owned(),
        r#"{"what":"timezone","zone":"Europe/Paris; reboot"}"#.to_owned(),
        r#"{"what":"timezone","zone":""}"#.to_owned(),
        r#"{"what":"timezone","zone":"--secret-file"}"#.to_owned(),
        r#"{"what":"wifi-add","ssid":"kura-ethernet","password":"long enough","hidden":false}"#.to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50/24","gateway":"0.0.0.0","dns":["1.1.1.1"]}"#.to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50/24","gateway":"192.168.1.1","dns":["0.0.0.0"]}"#
            .to_owned(),
        r#"{"what":"wifi-add","ssid":";evil","password":"long enough","hidden":false}"#.to_owned(),
        r#"{"what":"wifi-add","ssid":"Attic","password":"short","hidden":false}"#.to_owned(),
        r#"{"what":"wifi-add","ssid":"Attic","password":"two\nlines here","hidden":false}"#.to_owned(),
        r#"{"what":"wifi-remove","ssid":"--all"}"#.to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50","gateway":"192.168.1.1","dns":["1.1.1.1"]}"#.to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50/33","gateway":"192.168.1.1","dns":["1.1.1.1"]}"#
            .to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.256/24","gateway":"192.168.1.1","dns":["1.1.1.1"]}"#
            .to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50/24","gateway":"router","dns":["1.1.1.1"]}"#.to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50/24","gateway":"192.168.1.1","dns":[]}"#.to_owned(),
        r#"{"what":"ethernet-static","address":"192.168.1.50/24","gateway":"192.168.1.1","dns":["1.1.1.1,2.2.2.2"]}"#
            .to_owned(),
        r#"{"what":"user-add","name":"Carl","password":"x","admin":false}"#.to_owned(),
        r#"{"what":"user-add","name":"carl","password":"","admin":false}"#.to_owned(),
        r#"{"what":"user-add","name":"carl","password":"a\nroot:x","admin":false}"#.to_owned(),
        r#"{"what":"user-remove","name":"-rf"}"#.to_owned(),
        r#"{"what":"user-password","name":"carl","password":"a\u0000b"}"#.to_owned(),
    ];
    for json in bad {
        assert!(change(&json).command().is_err(), "{json}");
    }
}

#[test]
fn shapes_that_are_not_a_change_do_not_parse() {
    for json in [
        r#"{"what":"format-disk"}"#,
        r#"{"what":"hostname"}"#,
        r#"{"what":"hostname","name":"a","extra":1}"#,
        r#"{"what":"ntp","on":"yes"}"#,
        r#"{"name":"a"}"#,
        "[]",
    ] {
        assert!(serde_json::from_str::<Change>(json).is_err(), "{json}");
    }
}
