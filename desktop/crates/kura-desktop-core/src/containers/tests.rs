use super::*;

const LIST: &str = r#"[
 {"Id":"aaaaaaaaaaaa1111","Names":["/immich-server"],"Image":"ghcr.io/immich-app/immich-server:v2","State":"running",
  "Status":"Up 3 days","Created":1700000000,
  "Labels":{"com.docker.compose.project":"immich","com.docker.compose.service":"server"},
  "Ports":[{"PrivatePort":2283,"PublicPort":2283,"Type":"tcp"},{"IP":"::","PrivatePort":2283,"PublicPort":2283,"Type":"tcp"},{"PrivatePort":9000,"Type":"tcp"}]},
 {"Id":"bbbbbbbbbbbb2222","Names":[],"Image":"busybox","State":"exited","Status":"Exited (0) 2 hours ago","Created":1700000100}
]"#;

#[test]
fn parses_dockers_list() {
    let list = parse_list(LIST.as_bytes()).unwrap();
    assert_eq!(list.len(), 2);
    let a = &list[0];
    assert_eq!((a.id.as_str(), a.name.as_str(), a.state.as_str()), ("aaaaaaaaaaaa1111", "immich-server", "running"));
    assert_eq!((a.project.as_deref(), a.service.as_deref()), (Some("immich"), Some("server")));
    assert_eq!((a.ports.as_slice(), a.created), (&[2283u16][..], 1_700_000_000_000));
    let b = &list[1];
    assert_eq!((b.name.as_str(), b.project.as_deref(), b.ports.len()), ("bbbbbbbbbbbb", None, 0));
    assert!(parse_list(b"{not json").is_err());
}

#[test]
fn serializes_like_the_interface() {
    let list = parse_list(LIST.as_bytes()).unwrap();
    let json = serde_json::to_value(&list[1]).unwrap();
    assert_eq!(
        json,
        serde_json::json!({"id":"bbbbbbbbbbbb2222","name":"bbbbbbbbbbbb","image":"busybox","state":"exited",
            "status":"Exited (0) 2 hours ago","created":1_700_000_100_000i64,"project":null,"service":null,"ports":[]})
    );
}

#[test]
fn container_ids_and_actions() {
    let cases = [
        ("aaaaaaaaaaaa", true),
        (&"0123456789abcdef".repeat(4), true),
        ("aaaaaaaaaaa", false),
        (&"a".repeat(65), false),
        ("AAAAAAAAAAAA", false),
        ("aaaaaaaaaaaa/../x", false),
        ("", false),
    ];
    for (id, want) in cases {
        assert_eq!(valid_container_id(id), want, "{id}");
    }
    for (text, want) in [
        ("start", Some(ContainerAction::Start)),
        ("stop", Some(ContainerAction::Stop)),
        ("restart", Some(ContainerAction::Restart)),
        ("kill", None),
        ("", None),
    ] {
        assert_eq!(ContainerAction::parse(text), want);
        if let Some(a) = want {
            assert_eq!(a.as_str(), text);
        }
    }
}

fn frame(stream: u8, text: &str) -> Vec<u8> {
    let mut f = vec![stream, 0, 0, 0];
    f.extend((text.len() as u32).to_be_bytes());
    f.extend(text.as_bytes());
    f
}

#[test]
fn parses_multiplexed_logs_with_timestamps() {
    let mut raw = frame(1, "2026-11-21T10:00:00.123456789Z ready\n");
    raw.extend(frame(2, "2026-11-21T10:00:01.5Z \x1b[31mfailed\x1b[0m to bind\n2026-11-21T10:00:02Z again\n"));
    raw.extend(frame(1, "no timestamp here\n"));
    let lines = parse_logs(&raw);
    let got: Vec<_> = lines.iter().map(|l| (l.t, l.stream, l.text.as_str())).collect();
    assert_eq!(
        got,
        [
            (Some(1_795_255_200_123), "stdout", "ready"),
            (Some(1_795_255_201_500), "stderr", "failed to bind"),
            (Some(1_795_255_202_000), "stderr", "again"),
            (None, "stdout", "no timestamp here"),
        ]
    );
}

#[test]
fn parses_raw_tty_logs_and_survives_bad_input() {
    let lines = parse_logs(b"2026-11-21T10:00:00Z hello\r\n2026-11-21T10:00:00Z \xff\xfe bytes\n");
    assert_eq!(lines.len(), 2);
    assert_eq!((lines[0].stream, lines[0].text.as_str()), ("stdout", "hello"));
    assert!(lines[1].text.ends_with("bytes"));
    // a frame that claims more than there is: what is there is kept
    let mut cut = frame(1, "2026-11-21T10:00:00Z whole\n");
    cut.extend([1, 0, 0, 0, 0, 0, 1, 0]);
    cut.extend(b"2026-11-21T10:00:00Z part");
    assert_eq!(parse_logs(&cut).iter().map(|l| l.text.as_str()).collect::<Vec<_>>(), ["whole", "part"]);
    assert!(parse_logs(b"").is_empty());
    let long = format!("2026-11-21T10:00:00Z {}\n", "é".repeat(MAX_LINE_BYTES));
    assert!(parse_logs(long.as_bytes())[0].text.len() <= MAX_LINE_BYTES);
}

#[test]
fn text_that_could_mislead_is_cleaned() {
    let cases = [
        ("plain\ttabbed", "plain\ttabbed"),
        ("\x1b[1;31mred\x1b[0m", "red"),
        ("bell\x07 and title \x1b]0;x\x07", "bell and title 0;x"),
        ("user=admin\u{202e}nimda", "user=adminnimda"),
        ("iso\u{2066}late\u{2069}", "isolate"),
        ("c1\u{9b}31m", "c131m"),
    ];
    for (raw, want) in cases {
        assert_eq!(clean(raw), want, "{raw:?}");
    }
}

#[test]
fn rfc3339_to_milliseconds() {
    let cases = [
        ("1970-01-01T00:00:00Z", Some(0)),
        ("2000-02-29T12:00:00.250Z", Some(951_825_600_250)),
        ("2026-11-21T10:00:00.123456789Z", Some(1_795_255_200_123)),
        ("2026-11-21T10:00:00+01:00", None),
        ("2026-13-21T10:00:00Z", None),
        ("yesterday", None),
        ("", None),
    ];
    for (text, want) in cases {
        assert_eq!(rfc3339_ms(text), want, "{text}");
    }
}
