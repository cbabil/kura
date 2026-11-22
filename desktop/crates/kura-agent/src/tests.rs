use std::fs;
use std::io::Cursor;

use kura_desktop_core::files::{CHUNK, Failure, Reply, Request, read_frame, write_frame};

use super::*;

pub(crate) struct Rig {
    agent: Agent,
    dir: tempfile::TempDir,
}

pub(crate) fn rig() -> Rig {
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir_all(dir.path().join("home/chris/docs")).unwrap();
    fs::write(dir.path().join("home/chris/docs/a.txt"), "alpha").unwrap();
    Rig { agent: Agent::jailed("/home/chris".into(), dir.path().to_owned()), dir }
}

impl Rig {
    /// Sends one request (with `data` after a write); the reply and its bytes.
    fn ask_with(&self, request: &Request, data: Option<&[u8]>) -> (Reply, Option<Vec<u8>>) {
        let mut wire = Vec::new();
        write_frame(&mut wire, &serde_json::to_vec(request).unwrap()).unwrap();
        if let Some(data) = data {
            write_frame(&mut wire, data).unwrap();
        }
        let mut out = Vec::new();
        self.agent.serve(&mut Cursor::new(wire), &mut out).unwrap();
        let mut out = Cursor::new(out);
        let reply: Reply = serde_json::from_slice(&read_frame(&mut out).unwrap().unwrap()).unwrap();
        let bytes = if reply.data { read_frame(&mut out).unwrap() } else { None };
        (reply, bytes)
    }

    pub(crate) fn ask(&self, request: Request) -> Reply {
        self.ask_with(&request, None).0
    }

    pub(crate) fn at(&self, path: &str) -> std::path::PathBuf {
        self.dir.path().join(path.trim_start_matches('/'))
    }
}

pub(crate) fn path(p: &str) -> String {
    p.to_owned()
}

#[test]
fn says_hello_and_lists_a_folder() {
    let rig = rig();
    assert_eq!(rig.ask(Request::Hello).home.as_deref(), Some("/home/chris"));
    std::os::unix::fs::symlink("docs", rig.at("/home/chris/link")).unwrap();
    std::os::unix::fs::symlink("nowhere", rig.at("/home/chris/broken")).unwrap();
    let mut entries = rig.ask(Request::List { path: path("/home/chris") }).entries.unwrap();
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    let seen: Vec<(&str, bool, bool)> = entries.iter().map(|e| (e.name.as_str(), e.dir, e.link)).collect();
    assert_eq!(seen, [("broken", false, true), ("docs", true, false), ("link", true, true)]);
    let files = rig.ask(Request::List { path: path("/home/chris/docs") }).entries.unwrap();
    assert_eq!((files[0].name.as_str(), files[0].size), ("a.txt", 5));
    assert!(files[0].modified > 1_600_000_000);
}

#[test]
fn refuses_what_is_not_a_path_and_reports_what_the_kernel_says() {
    let rig = rig();
    for bad in ["home", "/home/../etc", "/home/chris/./docs", ""] {
        assert_eq!(rig.ask(Request::List { path: path(bad) }).error, Some(Failure::Invalid), "{bad}");
    }
    assert_eq!(rig.ask(Request::List { path: path("/home/nobody") }).error, Some(Failure::NotFound));
    assert_eq!(rig.ask(Request::List { path: path("/home/chris/docs/a.txt") }).error, Some(Failure::Invalid));
    assert_eq!(rig.ask(Request::MakeDir { path: path("/home/chris/docs") }).error, Some(Failure::Exists));
    // Something that is not a request at all
    let mut wire = Vec::new();
    write_frame(&mut wire, br#"{"op":"exec","path":"/bin/sh"}"#).unwrap();
    let mut out = Vec::new();
    rig.agent.serve(&mut Cursor::new(wire), &mut out).unwrap();
    let reply: Reply = serde_json::from_slice(&read_frame(&mut Cursor::new(out)).unwrap().unwrap()).unwrap();
    assert_eq!(reply.error, Some(Failure::Invalid));
}

#[test]
fn makes_renames_copies_and_deletes() {
    let rig = rig();
    assert_eq!(rig.ask(Request::MakeDir { path: path("/home/chris/new") }).error, None);
    let rename = |from: &str, to: &str| rig.ask(Request::Rename { from: path(from), to: path(to) }).error;
    assert_eq!(rename("/home/chris/docs/a.txt", "/home/chris/new/b.txt"), None);
    assert_eq!(fs::read_to_string(rig.at("/home/chris/new/b.txt")).unwrap(), "alpha");
    assert_eq!(rename("/home/chris/new", "/home/chris/docs"), Some(Failure::Exists), "never onto something");
    assert_eq!(rename("/home/chris/gone", "/home/chris/x"), Some(Failure::NotFound));

    std::os::unix::fs::symlink("b.txt", rig.at("/home/chris/new/link")).unwrap();
    fs::create_dir(rig.at("/home/chris/new/deep")).unwrap();
    fs::write(rig.at("/home/chris/new/deep/c.txt"), "gamma").unwrap();
    let copy = |from: &str, to: &str| rig.ask(Request::Copy { from: path(from), to: path(to) }).error;
    assert_eq!(copy("/home/chris/new", "/home/chris/copy"), None);
    assert_eq!(fs::read_to_string(rig.at("/home/chris/copy/deep/c.txt")).unwrap(), "gamma");
    assert!(rig.at("/home/chris/copy/link").symlink_metadata().unwrap().is_symlink(), "a link stays a link");
    assert_eq!(copy("/home/chris/new", "/home/chris/copy"), Some(Failure::Exists));
    assert_eq!(copy("/home/chris/new", "/home/chris/new/inside"), Some(Failure::Invalid), "not into itself");
    assert_eq!(copy("/home/chris/gone", "/home/chris/y"), Some(Failure::NotFound));
    // A folder keeps its rights, and a closed one can still be deleted.
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(rig.at("/home/chris/new/deep"), fs::Permissions::from_mode(0o500)).unwrap();
    assert_eq!(copy("/home/chris/new", "/home/chris/kept"), None);
    assert_eq!(rig.at("/home/chris/kept/deep").metadata().unwrap().permissions().mode() & 0o777, 0o500);
    assert_eq!(rig.ask(Request::Delete { path: path("/home/chris/kept") }).error, None);
    fs::set_permissions(rig.at("/home/chris/new/deep"), fs::Permissions::from_mode(0o755)).unwrap();

    assert_eq!(rig.ask(Request::Delete { path: path("/home/chris/copy") }).error, None);
    assert!(!rig.at("/home/chris/copy").exists());
    assert_eq!(rig.ask(Request::Delete { path: path("/home/chris/new/link") }).error, None);
    assert!(rig.at("/home/chris/new/b.txt").exists(), "deleting a link leaves what it leads to");
    assert_eq!(rig.ask(Request::Delete { path: path("/home/chris/copy") }).error, Some(Failure::NotFound));
}

#[test]
fn reads_a_file_in_pieces() {
    let rig = rig();
    let big: Vec<u8> = (0..CHUNK + 10).map(|i| (i % 251) as u8).collect();
    fs::write(rig.at("/home/chris/big.bin"), &big).unwrap();
    let read = |offset: u64| rig.ask_with(&Request::Read { path: path("/home/chris/big.bin"), offset }, None);
    let (first, bytes) = read(0);
    assert_eq!((first.size, bytes.as_deref()), (Some(big.len() as u64), Some(&big[..CHUNK])));
    assert_eq!(read(CHUNK as u64).1.as_deref(), Some(&big[CHUNK..]));
    assert_eq!(read(big.len() as u64 + 5).1.as_deref(), Some(&[][..]), "past the end is no bytes");
    // A pipe is refused at once, not waited on.
    let fifo = std::ffi::CString::new(rig.at("/home/chris/pipe").to_str().unwrap()).unwrap();
    // SAFETY: a valid, NUL-ended path; mkfifo only makes the node.
    assert_eq!(unsafe { libc::mkfifo(fifo.as_ptr(), 0o600) }, 0);
    assert_eq!(rig.ask(Request::Read { path: path("/home/chris/pipe"), offset: 0 }).error, Some(Failure::Invalid));
    let folder = rig.ask(Request::Read { path: path("/home/chris/docs"), offset: 0 });
    assert_eq!(folder.error, Some(Failure::Invalid));
    assert_eq!(rig.ask(Request::Read { path: path("/home/chris/none"), offset: 0 }).error, Some(Failure::NotFound));
}

#[test]
fn a_new_file_appears_whole_with_its_last_piece() {
    let rig = rig();
    let target = "/home/chris/docs/up.bin";
    let write = |offset: u64, last: bool, data: &[u8]| {
        rig.ask_with(&Request::Write { path: path(target), id: path("up1"), offset, last }, Some(data)).0.error
    };
    assert_eq!(write(0, false, b"hello "), None);
    assert!(!rig.at(target).exists(), "not there until it is whole");
    assert_eq!(write(3, false, b"xxx"), Some(Failure::Invalid), "a piece out of order");
    assert!(!rig.at("/home/chris/docs/.up.bin.up1.kura-upload").exists(), "and the part is dropped");
    assert_eq!(write(0, false, b"hello "), None);
    assert_eq!(write(6, true, b"world"), None);
    assert_eq!(fs::read(rig.at(target)).unwrap(), b"hello world");
    assert!(!rig.at("/home/chris/docs/.up.bin.up1.kura-upload").exists());
    // Two uploads of one name do not mix, and a planted link is not followed.
    let other = |id: &str, offset: u64, last: bool, data: &[u8]| {
        let request = Request::Write { path: path("/home/chris/docs/two.bin"), id: path(id), offset, last };
        rig.ask_with(&request, Some(data)).0.error
    };
    assert_eq!((other("a", 0, false, b"AA"), other("b", 0, false, b"BBBB")), (None, None));
    assert_eq!(other("a", 2, true, b"aa"), None);
    assert_eq!(fs::read(rig.at("/home/chris/docs/two.bin")).unwrap(), b"AAaa");
    assert_eq!(other("b", 4, true, b"bb"), Some(Failure::Exists), "the first one took the name");
    assert_eq!(other("../x", 0, true, b""), Some(Failure::Invalid));
    fs::write(rig.at("/home/chris/victim"), "mine").unwrap();
    std::os::unix::fs::symlink(rig.at("/home/chris/victim"), rig.at("/home/chris/docs/.three.c.kura-upload")).unwrap();
    let planted = Request::Write { path: path("/home/chris/docs/three"), id: path("c"), offset: 0, last: true };
    assert_eq!(rig.ask_with(&planted, Some(b"overwritten")).0.error, Some(Failure::Exists));
    assert_eq!(fs::read_to_string(rig.at("/home/chris/victim")).unwrap(), "mine");
    assert_eq!(write(0, true, b"again"), Some(Failure::Exists), "nothing is written over");
    assert_eq!(fs::read(rig.at(target)).unwrap(), b"hello world");
    let too_much = vec![0u8; CHUNK + 1];
    let other = Request::Write { path: path("/home/chris/docs/o.bin"), id: path("o"), offset: 0, last: true };
    assert_eq!(rig.ask_with(&other, Some(&too_much)).0.error, Some(Failure::Invalid));
    let empty = Request::Write { path: path("/home/chris/docs/empty"), id: path("e"), offset: 0, last: true };
    assert_eq!(rig.ask_with(&empty, Some(b"")).0.error, None);
    assert_eq!(fs::read(rig.at("/home/chris/docs/empty")).unwrap(), b"");
}

#[test]
fn several_requests_are_answered_in_order_and_a_cut_stream_is_an_error() {
    let rig = rig();
    let mut wire = Vec::new();
    for request in [Request::Hello, Request::List { path: path("/home/chris") }] {
        write_frame(&mut wire, &serde_json::to_vec(&request).unwrap()).unwrap();
    }
    let mut out = Vec::new();
    rig.agent.serve(&mut Cursor::new(wire.clone()), &mut out).unwrap();
    let mut out = Cursor::new(out);
    let first: Reply = serde_json::from_slice(&read_frame(&mut out).unwrap().unwrap()).unwrap();
    let second: Reply = serde_json::from_slice(&read_frame(&mut out).unwrap().unwrap()).unwrap();
    assert!(first.home.is_some() && second.entries.is_some());
    assert!(rig.agent.serve(&mut Cursor::new(wire[..6].to_vec()), &mut Vec::new()).is_err());
    assert_eq!(Agent::new("/home/x".into()).real("/etc/hosts").unwrap(), std::path::PathBuf::from("/etc/hosts"));
}
