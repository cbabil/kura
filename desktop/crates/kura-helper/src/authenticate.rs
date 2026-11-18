//! The policy around PAM: refuse malformed input before PAM sees it, run one
//! check at a time, and report `sudo` membership as `admin`.

use std::sync::Mutex;

use kura_desktop_core::accounts::Accounts;
use kura_desktop_core::auth::{AuthOutcome, well_formed};
use kura_desktop_core::root::SysRoot;

/// What PAM said about a user name and password.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PamVerdict {
    /// Authenticated and the account may sign in.
    Ok,
    /// Refused: wrong password, unknown or locked user, or any PAM error.
    Wrong,
    /// Authenticated, but the password must be changed first.
    Expired,
}

/// A password check; the real one is [`crate::pam::LinuxPam`].
pub trait Pam: Send + Sync {
    /// Checks `password` for `user`. Blocking: PAM may sleep after a failure.
    fn check(&self, user: &str, password: &str) -> PamVerdict;
}

/// The group whose members are administrators.
pub const ADMIN_GROUP: &str = "sudo";
/// The lowest uid of a person's account (Debian's `FIRST_UID`); root and
/// system accounts cannot sign in over the network.
pub const MIN_UID: u32 = 1000;
/// `nobody`, which is above [`MIN_UID`] but is not a person.
const NOBODY: u32 = 65534;

/// Checks passwords with a [`Pam`] and looks up `admin`.
pub struct Authenticator {
    pam: Box<dyn Pam>,
    root: SysRoot,
    /// PAM runs one transaction at a time, which also slows guessing.
    one_at_a_time: Mutex<()>,
}

impl Authenticator {
    /// An authenticator reading `/etc/group` under `root`.
    pub fn new(pam: Box<dyn Pam>, root: SysRoot) -> Self {
        Self { pam, root, one_at_a_time: Mutex::new(()) }
    }

    /// Checks a sign-in. Blocking. Only people's accounts (uid from
    /// [`MIN_UID`], not `nobody`) are checked at all.
    pub fn authenticate(&self, user: &str, password: &str) -> AuthOutcome {
        let accounts = Accounts::load(&self.root);
        let person = accounts.by_name(user).is_some_and(|a| a.uid >= MIN_UID && a.uid != NOBODY);
        if !person || !well_formed(user, password) {
            return AuthOutcome::Wrong;
        }
        let verdict = {
            let _turn = self.one_at_a_time.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            self.pam.check(user, password)
        };
        match verdict {
            PamVerdict::Ok => AuthOutcome::Ok { admin: accounts.in_group(user, ADMIN_GROUP) },
            PamVerdict::Wrong => AuthOutcome::Wrong,
            PamVerdict::Expired => AuthOutcome::Expired,
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// Accepts "kura" for every user; "old" has an expired password.
    pub(crate) struct FakePam;
    impl Pam for FakePam {
        fn check(&self, user: &str, password: &str) -> PamVerdict {
            match (user, password) {
                (_, p) if p != "kura" => PamVerdict::Wrong,
                ("old", _) => PamVerdict::Expired,
                _ => PamVerdict::Ok,
            }
        }
    }

    /// People anna, bob and old, plus root, a system account and nobody.
    pub(crate) const PASSWD: &str = "root:x:0:0::/root:/bin/sh\ndaemon:x:1:1::/:/bin/sh\n\
        anna:x:1000:1000::/home/anna:/bin/sh\nbob:x:1001:1001::/home/bob:/bin/sh\n\
        old:x:1002:1002::/home/old:/bin/sh\nnobody:x:65534:65534::/:/bin/sh\n";

    pub(crate) fn authenticator() -> (Authenticator, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("etc")).unwrap();
        std::fs::write(dir.path().join("etc/group"), "sudo:x:27:anna\n").unwrap();
        std::fs::write(dir.path().join("etc/passwd"), PASSWD).unwrap();
        (Authenticator::new(Box::new(FakePam), SysRoot::new(dir.path())), dir)
    }

    #[test]
    fn outcomes() {
        let (a, _dir) = authenticator();
        let long = "k".repeat(kura_desktop_core::auth::MAX_PASSWORD_BYTES + 1);
        let cases = [
            ("anna", "kura", AuthOutcome::Ok { admin: true }),
            ("bob", "kura", AuthOutcome::Ok { admin: false }),
            ("bob", "nope", AuthOutcome::Wrong),
            ("old", "kura", AuthOutcome::Expired),
            ("Bad Name", "kura", AuthOutcome::Wrong),
            ("bob", "", AuthOutcome::Wrong),
            ("bob", "ku\0ra", AuthOutcome::Wrong),
            ("bob", long.as_str(), AuthOutcome::Wrong),
            ("root", "kura", AuthOutcome::Wrong),
            ("daemon", "kura", AuthOutcome::Wrong),
            ("nobody", "kura", AuthOutcome::Wrong),
            ("ghost", "kura", AuthOutcome::Wrong),
        ];
        for (user, password, want) in cases {
            assert_eq!(a.authenticate(user, password), want, "{user}");
        }
    }
}
