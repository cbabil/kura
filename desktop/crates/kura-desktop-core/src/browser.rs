//! The shared Browser (ADR-036): Debian's Chromium on this machine, in
//! TigerVNC's X server, run by `kura-browser.service` as its own account.
//! The VNC server listens on a unix socket only, which `kura-desktop` may
//! open; desktopd relays it to the WebSocket `/api/browser`.

use crate::root::SysRoot;

/// The unit the helper starts and stops; nothing else is ever named.
pub const UNIT: &str = "kura-browser.service";
/// Where the unit's VNC server listens.
pub const SOCKET: &str = "/run/kura-browser/vnc.sock";
/// The programs the unit needs (the image's `OS_BROWSER` packages). The
/// unit, its account and its command are on every PC; these may not be.
pub const PROGRAMS: [&str; 4] =
    ["/usr/bin/Xtigervnc", "/usr/bin/chromium", "/usr/bin/matchbox-window-manager", "/usr/bin/xauth"];

/// True when this machine can run the Browser: its unit and every program
/// it needs are there. The dock shows the app only then.
pub fn available(root: &SysRoot) -> bool {
    root.has_unit(UNIT, &PROGRAMS)
}

/// Every file [`available`] looks for, as absolute paths: what a test or the
/// development root makes to stand for an image with the Browser.
pub fn files() -> impl Iterator<Item = String> {
    std::iter::once(format!("/usr/lib/systemd/system/{UNIT}")).chain(PROGRAMS.map(String::from))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn available_only_with_the_unit_and_every_program() {
        let dir = tempfile::tempdir().unwrap();
        let root = SysRoot::new(dir.path());
        let mut made = 0;
        for file in files() {
            assert!(!available(&root), "{made} of the files");
            let path = root.path(&file);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, "").unwrap();
            made += 1;
        }
        assert!(available(&root));
        assert_eq!(made, 1 + PROGRAMS.len());
    }
}
