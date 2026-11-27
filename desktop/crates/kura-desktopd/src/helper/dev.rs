//! A stand-in for `kura-helper`, for development on a Mac and for tests. It
//! is the real helper's [`Service`], so every rule is the real one, over
//! backends that need no Linux: a fake password check, sample containers and
//! a sample journal, a shell of the person running desktopd, and a machine
//! that only notes what it was asked.
//!
//! The accounts are [`ACCOUNTS`]; all sign in with [`DEV_PASSWORD`].

mod apps;
mod backends;
mod browsers;
mod sample;
mod shell;
mod system;

use std::os::fd::OwnedFd;
use std::sync::Arc;

use kura_desktop_core::actions::Action;
use kura_desktop_core::auth::AuthOutcome;
use kura_desktop_core::root::SysRoot;
use kura_helper::refusal::Refusal;
use kura_helper::{Authenticator, Backends, Service};
use zeroize::Zeroizing;

use super::{Fut, Helper, HelperError};

/// The development password.
pub const DEV_PASSWORD: &str = "kura";
/// The user who is not an administrator.
pub const GUEST: &str = "guest";

/// The development accounts, `(name, uid, administrator)`: "expired" must
/// change its password first, and "noshell" has no login shell.
pub const ACCOUNTS: [(&str, u32, bool); 6] = [
    ("kura", 1000, true),
    ("chris", 1001, true),
    ("anna", 1002, true),
    (GUEST, 1003, false),
    ("expired", 1004, false),
    ("noshell", 1005, false),
];

/// The helper's service over development backends.
pub struct DevHelper {
    service: Service,
    /// Holds `/etc/passwd`, `group` and `shells` for [`ACCOUNTS`].
    _accounts: tempfile::TempDir,
}

impl Default for DevHelper {
    fn default() -> Self {
        let shell = std::env::var("SHELL").ok().filter(|s| !s.is_empty());
        Self::with_shell(shell.as_deref().unwrap_or("/bin/sh"))
    }
}

impl DevHelper {
    /// A helper whose terminals run `shell`.
    ///
    /// # Panics
    /// Panics when the temporary folder for the accounts cannot be made:
    /// nothing in development works without it.
    pub fn with_shell(shell: &str) -> Self {
        let dir = tempfile::tempdir().expect("a temporary folder for the development accounts");
        let etc = dir.path().join("etc");
        let line = |(name, uid, _): &(&str, u32, bool)| {
            let login = if *name == "noshell" { "/usr/sbin/nologin" } else { shell };
            format!("{name}:x:{uid}:{uid}::/home/{name}:{login}\n")
        };
        let admins: Vec<&str> = ACCOUNTS.iter().filter(|a| a.2).map(|a| a.0).collect();
        let files = [
            ("passwd", ACCOUNTS.iter().map(line).collect::<String>()),
            ("group", format!("sudo:x:27:{}\n", admins.join(","))),
            ("shells", format!("{shell}\n")),
        ];
        std::fs::create_dir(&etc).expect("the accounts folder");
        for (name, text) in files {
            std::fs::write(etc.join(name), text).expect("an accounts file");
        }
        // The version this "device" runs, as the image's release file has it.
        let lib = dir.path().join("usr/lib/kura");
        std::fs::create_dir_all(&lib).expect("the release folder");
        std::fs::write(lib.join("release"), "BRAND_VERSION=\"0.6.1\"\n").expect("the release file");
        // Kura's configuration and state, which Settings reads and changes.
        std::fs::create_dir_all(etc.join("kura")).expect("the configuration folder");
        std::fs::write(etc.join("kura/config.json"), system::FIRST_CONFIG).expect("the configuration");
        let state = dir.path().join("var/lib/kura");
        std::fs::create_dir_all(&state).expect("the state folder");
        std::fs::write(state.join("storage-status"), "applied\n").expect("the layout status");
        // The development "image" has the local screen, off (ADR-033).
        let units = dir.path().join("usr/lib/systemd/system");
        std::fs::create_dir_all(&units).expect("the units folder");
        std::fs::write(units.join("kura-kiosk.service"), "").expect("the local screen's unit");
        std::fs::create_dir_all(dir.path().join("usr/bin")).expect("the programs folder");
        std::fs::write(dir.path().join("usr/bin/cage"), "").expect("the local screen's program");
        // ...and Remote Desktop, off (ADR-035).
        std::fs::write(units.join("xrdp.service"), "").expect("Remote Desktop's unit");
        std::fs::create_dir_all(dir.path().join("usr/sbin")).expect("the system programs folder");
        std::fs::write(dir.path().join("usr/sbin/xrdp"), "").expect("Remote Desktop's program");
        // ...and the Browser's command and programs (ADR-036): a stand-in
        // VNC server answers for it (browsers.rs).
        for file in kura_desktop_core::browser::files() {
            std::fs::write(dir.path().join(file.trim_start_matches('/')), "").expect("a Browser file");
        }
        let root = SysRoot::new(dir.path());
        let auth = Arc::new(Authenticator::new(Box::new(backends::DevPam), root.clone()));
        let backends = Backends {
            docker: Arc::new(backends::SampleDocker::default()),
            journal: Arc::new(backends::SampleJournal),
            shells: Arc::new(shell::LocalShell::new(shell, dir.path().to_owned())),
            machine: Arc::new(backends::DevMachine::default()),
            system: Arc::new(system::DevSystem::new(dir.path().to_owned())),
            apps: Arc::new(apps::DevApps::new(dir.path().to_owned()).expect("the development catalog")),
            browsers: Arc::new(browsers::DevBrowsers::default()),
        };
        Self { service: Service::new(auth, root, backends), _accounts: dir }
    }
}

impl From<Refusal> for HelperError {
    fn from(refusal: Refusal) -> Self {
        Self::from_refused(refusal.kind(), &refusal.to_string())
    }
}

impl Helper for DevHelper {
    fn authenticate<'a>(&'a self, user: &'a str, password: &'a str) -> Fut<'a, (AuthOutcome, String)> {
        Box::pin(
            async move { Ok(self.service.authenticate(user.to_owned(), Zeroizing::new(password.to_owned())).await) },
        )
    }

    fn keep_alive<'a>(&'a self, ticket: &'a str) -> Fut<'a, ()> {
        Box::pin(async move { Ok(self.service.keep_alive(ticket)?) })
    }

    fn sign_out<'a>(&'a self, ticket: &'a str) -> Fut<'a, ()> {
        Box::pin(async move {
            self.service.sign_out(ticket).await;
            Ok(())
        })
    }

    fn open_terminal<'a>(&'a self, ticket: &'a str, cols: u16, rows: u16) -> Fut<'a, (String, OwnedFd)> {
        Box::pin(async move { Ok(self.service.open_terminal(ticket, cols, rows).await?) })
    }

    fn open_files<'a>(&'a self, ticket: &'a str) -> Fut<'a, (String, OwnedFd)> {
        Box::pin(async move { Ok(self.service.open_files(ticket).await?) })
    }

    fn close_terminal<'a>(&'a self, ticket: &'a str, id: &'a str) -> Fut<'a, ()> {
        Box::pin(async move { Ok(self.service.close_terminal(ticket, id).await?) })
    }

    fn open_browser<'a>(&'a self, ticket: &'a str) -> Fut<'a, OwnedFd> {
        Box::pin(async move { Ok(self.service.open_browser(ticket).await?) })
    }

    fn ask<'a>(&'a self, ticket: &'a str, action: Action, args: String) -> Fut<'a, String> {
        Box::pin(async move { Ok(self.service.ask(ticket, action.name(), &args).await?) })
    }
}
