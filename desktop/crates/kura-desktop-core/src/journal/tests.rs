use super::*;

fn query(lines: u32, unit: &str, priority: i32, after: &str) -> Result<JournalQuery, QueryError> {
    JournalQuery::new(lines, unit, priority, after)
}

#[test]
fn builds_journalctl_arguments() {
    let q = query(200, "", -1, "").unwrap();
    assert_eq!(q.to_args(), ["--output=json", "--all", "--no-pager", "--quiet", "--lines=200"]);
    let q = query(50, "ssh.service", 3, "s=ab12;i=1f;b=00;m=1;t=2;x=3").unwrap();
    assert_eq!(
        (q.lines(), q.unit(), q.priority(), q.after().map(str::len)),
        (50, Some("ssh.service"), Some(3), Some(28))
    );
    assert_eq!(
        q.to_args(),
        [
            "--output=json",
            "--all",
            "--no-pager",
            "--quiet",
            "--lines=50",
            "--unit=ssh.service",
            "--priority=3",
            "--after-cursor=s=ab12;i=1f;b=00;m=1;t=2;x=3"
        ]
    );
}

#[test]
fn refuses_anything_that_is_not_a_plain_filter() {
    let long_unit = format!("{}.service", "a".repeat(250));
    let bad = [
        (0, "", -1, ""),
        (MAX_LINES + 1, "", -1, ""),
        (10, "--file=/etc/shadow", -1, ""),
        (10, "a b.service", -1, ""),
        (10, "a;b.service", -1, ""),
        (10, long_unit.as_str(), -1, ""),
        (10, "", 8, ""),
        (10, "", -2, ""),
        (10, "", -1, "--since=1"),
        (10, "", -1, "s=1 x"),
    ];
    for (lines, unit, priority, after) in bad {
        assert!(query(lines, unit, priority, after).is_err(), "{lines} {unit} {priority} {after}");
    }
    for unit in
        ["getty@tty1.service", "systemd-fsck@dev-disk-by\\x2duuid-1.service", "docker.socket", "user@1000.service"]
    {
        assert!(query(10, unit, 7, "").is_ok(), "{unit}");
    }
}

const OUT: &str = concat!(
    r#"{"__CURSOR":"s=1;i=a","__REALTIME_TIMESTAMP":"1700000000123456","PRIORITY":"3","_SYSTEMD_UNIT":"ssh.service","SYSLOG_IDENTIFIER":"sshd","_PID":"640","MESSAGE":"Failed password"}"#,
    "\n",
    r#"{"__CURSOR":"s=1;i=b","__REALTIME_TIMESTAMP":"1700000001000000","_COMM":"kernel","MESSAGE":[104,105,255]}"#,
    "\nnot json\n",
    r#"{"__CURSOR":"s=1;i=c","__REALTIME_TIMESTAMP":"1700000002000000","PRIORITY":"9","UNIT":"x.service","MESSAGE":null}"#,
    "\n"
);

#[test]
fn parses_journalctl_json_lines() {
    let page = parse_page(OUT.as_bytes());
    assert_eq!(page.cursor.as_deref(), Some("s=1;i=c"));
    let got: Vec<_> = page
        .entries
        .iter()
        .map(|e| (e.t, e.priority, e.unit.as_str(), e.ident.as_str(), e.pid, e.message.as_str()))
        .collect();
    assert_eq!(
        got,
        [
            (1_700_000_000_123, 3, "ssh.service", "sshd", Some(640), "Failed password"),
            (1_700_000_001_000, 6, "", "kernel", None, "hi\u{fffd}"),
            (1_700_000_002_000, 6, "x.service", "", None, ""),
        ]
    );
    let empty = parse_page(b"");
    assert!(empty.entries.is_empty() && empty.cursor.is_none());
}

#[test]
fn serializes_like_the_interface() {
    let page = parse_page(OUT.lines().next().unwrap().as_bytes());
    assert_eq!(
        serde_json::to_value(&page).unwrap(),
        serde_json::json!({"cursor":"s=1;i=a","entries":[{"t":1_700_000_000_123i64,"priority":3,"unit":"ssh.service",
            "ident":"sshd","pid":640,"message":"Failed password"}]})
    );
}

#[test]
fn long_messages_are_cut() {
    let line = serde_json::json!({"__REALTIME_TIMESTAMP":"1","MESSAGE":"é".repeat(MAX_MESSAGE_BYTES)}).to_string();
    let page = parse_page(line.as_bytes());
    assert!(page.entries[0].message.len() <= MAX_MESSAGE_BYTES);
    let line = serde_json::json!({"__REALTIME_TIMESTAMP":"1","MESSAGE":"ok\u{1b}[31m \u{202e}evil\u{7}"}).to_string();
    assert_eq!(parse_page(line.as_bytes()).entries[0].message, "ok evil");
}
