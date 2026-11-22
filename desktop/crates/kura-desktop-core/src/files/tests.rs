use std::io::Cursor;

use super::*;

#[test]
fn paths_are_absolute_with_nothing_to_resolve() {
    for good in ["/", "/home/chris", "/srv/a b/été.txt", "/home/chris/.config", "/a/..b"] {
        assert!(valid_path(good), "{good}");
    }
    let long = format!("/{}", "a/".repeat(2100));
    for bad in ["", "home", "/home/../etc", "/home/./x", "/home//x", "/home/", "/a\0b", "..", long.as_str()] {
        assert!(!valid_path(bad), "{bad:?}");
    }
    for bad in ["", ".", "..", "a/b", "a\0", &"n".repeat(256)] {
        assert!(!valid_name(bad), "{bad:?}");
    }
    assert!(valid_name("Notes (2).txt"));
}

#[test]
fn a_path_splits_into_its_folder_and_name() {
    assert_eq!(split("/home/chris/a.txt"), Some(("/home/chris", "a.txt")));
    assert_eq!(split("/srv"), Some(("/", "srv")));
    assert_eq!(split("/"), None);
    assert_eq!(part_name("a.txt", "x1"), ".a.txt.x1.kura-upload");
    assert!(
        valid_upload_id("abc123")
            && !valid_upload_id("")
            && !valid_upload_id("a/b")
            && !valid_upload_id(&"a".repeat(33))
    );
    assert_eq!(percent_encode("/a b/é", "/"), "/a%20b/%C3%A9");
}

#[test]
fn requests_are_exactly_what_is_listed() {
    let read: Request = serde_json::from_str(r#"{"op":"read","path":"/a","offset":7}"#).unwrap();
    assert_eq!(read, Request::Read { path: "/a".into(), offset: 7 });
    assert_eq!(serde_json::to_string(&Request::ListTrash).unwrap(), r#"{"op":"list-trash"}"#);
    for bad in [r#"{"op":"exec","path":"/bin/sh"}"#, r#"{"op":"list","path":"/a","follow":true}"#, r#"{"op":"list"}"#] {
        assert!(serde_json::from_str::<Request>(bad).is_err(), "{bad}");
    }
}

#[test]
fn a_reply_carries_only_what_it_has() {
    assert_eq!(serde_json::to_string(&Reply::default()).unwrap(), "{}");
    assert_eq!(serde_json::to_string(&Reply::failed(Failure::OtherVolume)).unwrap(), r#"{"error":"other-volume"}"#);
    let back: Reply = serde_json::from_str(r#"{"size":3,"data":true}"#).unwrap();
    assert_eq!((back.size, back.data, back.error), (Some(3), true, None));
}

#[test]
fn frames_round_trip_and_bad_ones_are_errors() {
    let mut wire = Vec::new();
    write_frame(&mut wire, b"hello").unwrap();
    write_frame(&mut wire, b"").unwrap();
    let mut from = Cursor::new(wire.clone());
    assert_eq!(read_frame(&mut from).unwrap().as_deref(), Some(&b"hello"[..]));
    assert_eq!(read_frame(&mut from).unwrap().as_deref(), Some(&b""[..]));
    assert_eq!(read_frame(&mut from).unwrap(), None, "a clean end");

    assert!(write_frame(&mut Vec::new(), &vec![0; MAX_FRAME + 1]).is_err());
    let too_long = ((MAX_FRAME + 1) as u32).to_be_bytes();
    assert!(read_frame(&mut Cursor::new(too_long.to_vec())).is_err());
    assert!(read_frame(&mut Cursor::new(wire[..7].to_vec())).is_err(), "cut inside a frame");
    assert!(read_frame(&mut Cursor::new(wire[..2].to_vec())).is_err(), "cut inside a length");
}
