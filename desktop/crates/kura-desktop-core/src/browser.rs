//! The Browser (ADR-036): Debian's Chromium on this machine, one for each
//! person, run as that person in TigerVNC's X server, with its profile in
//! their home. The helper has systemd start it (`browser-<user>`, as
//! a terminal or the file agent is started); its VNC server listens on a
//! unix socket in a folder only that person can open, and the helper hands
//! desktopd a connection to it, which desktopd relays to `/api/browser`.

use crate::root::SysRoot;

/// The session command each person's unit runs (in every PC image).
pub const COMMAND: &str = "/usr/lib/kura/kura-browser";
/// The programs it needs (the image's `OS_BROWSER` packages), which a PC
/// may not have.
pub const PROGRAMS: [&str; 4] =
    ["/usr/bin/Xtigervnc", "/usr/bin/chromium", "/usr/bin/matchbox-window-manager", "/usr/bin/xauth"];

/// True when this machine can run the Browser: the command and every
/// program it needs are there. The dock shows the app only then.
pub fn available(root: &SysRoot) -> bool {
    files().all(|f| root.path(f).exists())
}

/// Every file [`available`] looks for, as absolute paths: what a test or the
/// development root makes to stand for an image with the Browser.
pub fn files() -> impl Iterator<Item = &'static str> {
    std::iter::once(COMMAND).chain(PROGRAMS)
}

/// The unit of `user`'s browser. User names are checked when they sign in
/// (`auth::valid_user_name`), so they are safe in a unit's name.
pub fn unit(user: &str) -> String {
    format!("browser-{user}.service")
}

/// The runtime folder of `user`'s browser, under `/run`: theirs alone (0700).
pub fn runtime_dir(user: &str) -> String {
    format!("browser-{user}")
}

/// Where `user`'s VNC server listens.
pub fn socket(user: &str) -> String {
    format!("/run/{}/vnc.sock", runtime_dir(user))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn available_only_with_the_command_and_every_program() {
        let dir = tempfile::tempdir().unwrap();
        let root = SysRoot::new(dir.path());
        let mut made = 0;
        for file in files() {
            assert!(!available(&root), "{made} of the files");
            let path = root.path(file);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, "").unwrap();
            made += 1;
        }
        assert!(available(&root));
        assert_eq!(made, 1 + PROGRAMS.len());
    }

    #[test]
    fn each_person_has_their_own_unit_and_socket() {
        assert_eq!(unit("anna"), "browser-anna.service");
        assert_eq!(socket("anna"), "/run/browser-anna/vnc.sock");
        assert_ne!(socket("anna"), socket("bob"));
    }
}
