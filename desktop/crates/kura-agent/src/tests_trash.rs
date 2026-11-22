use std::fs;

use kura_desktop_core::files::{Failure, Request};

use crate::tests::{path, rig};

#[test]
fn the_trash_keeps_restores_and_empties() {
    let rig = rig();
    assert_eq!(rig.ask(Request::ListTrash).trash.unwrap(), [], "no trash yet is an empty one");
    fs::write(rig.at("/home/chris/a.txt"), "other").unwrap();
    assert_eq!(rig.ask(Request::Trash { path: path("/home/chris/docs/a.txt") }).error, None);
    assert_eq!(rig.ask(Request::Trash { path: path("/home/chris/a.txt") }).error, None);
    assert_eq!(rig.ask(Request::Trash { path: path("/home/chris/docs") }).error, None);
    assert!(!rig.at("/home/chris/docs").exists());
    let record = fs::read_to_string(rig.at("/home/chris/.local/share/Trash/info/a.txt.trashinfo")).unwrap();
    assert!(record.starts_with("[Trash Info]\nPath=/home/chris/docs/a.txt\nDeletionDate=20"), "{record}");

    let mut trash = rig.ask(Request::ListTrash).trash.unwrap();
    trash.sort_by(|a, b| a.name.cmp(&b.name));
    let seen: Vec<(&str, &str, bool)> = trash.iter().map(|t| (t.name.as_str(), t.path.as_str(), t.dir)).collect();
    let expected = [
        ("a.txt", "/home/chris/docs/a.txt", false),
        ("a.txt.2", "/home/chris/a.txt", false),
        ("docs", "/home/chris/docs", true),
    ];
    assert_eq!(seen, expected);

    let restore = |name: &str| rig.ask(Request::Restore { name: path(name) }).error;
    assert_eq!(restore("a.txt"), Some(Failure::NotFound), "its folder is in the trash too");
    assert_eq!(restore("docs"), None);
    assert_eq!(restore("a.txt"), None);
    assert_eq!(fs::read_to_string(rig.at("/home/chris/docs/a.txt")).unwrap(), "alpha");
    fs::write(rig.at("/home/chris/a.txt"), "newer").unwrap();
    assert_eq!(restore("a.txt.2"), Some(Failure::Exists), "nothing is written over");
    assert_eq!(restore("../info/a.txt.2.trashinfo"), Some(Failure::Invalid));
    assert_eq!(restore("never"), Some(Failure::NotFound));

    assert_eq!(
        rig.ask(Request::Trash { path: path("/home/chris/.local/share/Trash/files/a.txt.2") }).error,
        Some(Failure::Invalid)
    );
    assert_eq!(
        rig.ask(Request::Trash { path: path("/home/chris") }).error,
        Some(Failure::Invalid),
        "not the trash's own home"
    );
    assert_eq!(rig.ask(Request::Trash { path: path("/home/chris/gone") }).error, Some(Failure::NotFound));
    let own = Request::Trash { path: path("/home/chris/.local/share/Trash/info") };
    assert_eq!(rig.ask(own).error, Some(Failure::Invalid));
    // A read-only folder in the trash does not keep it from being emptied.
    use std::os::unix::fs::PermissionsExt;
    fs::create_dir_all(rig.at("/home/chris/locked/in")).unwrap();
    assert_eq!(rig.ask(Request::Trash { path: path("/home/chris/locked") }).error, None);
    let trashed = rig.at("/home/chris/.local/share/Trash/files/locked");
    fs::set_permissions(trashed, fs::Permissions::from_mode(0o500)).unwrap();
    assert_eq!(rig.ask(Request::EmptyTrash).error, None);
    assert_eq!(rig.ask(Request::ListTrash).trash.unwrap(), []);
    assert!(fs::read_dir(rig.at("/home/chris/.local/share/Trash/files")).unwrap().next().is_none());
}
