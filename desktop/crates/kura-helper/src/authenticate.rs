//! The policy around PAM: refuse malformed input before PAM sees it, run one
//! check at a time, and report `sudo` membership as `admin`.

use std::sync::Mutex;

use kura_desktop_core::accounts::Accounts;
use kura_desktop_core::auth::{AuthOutcome, MAX_PASSWORD_BYTES, valid_user_name};
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

    /// Checks a sign-in. Blocking.
    pub fn authenticate(&self, user: &str, password: &str) -> AuthOutcome {
        let well_formed = valid_user_name(user)
            && !password.is_empty()
            && password.len() <= MAX_PASSWORD_BYTES
            && !password.contains('\0');
        if !well_formed {
            return AuthOutcome::Wrong;
        }
        let verdict = {
            let _turn = self.one_at_a_time.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            self.pam.check(user, password)
        };
        match verdict {
            PamVerdict::Ok => AuthOutcome::Ok { admin: Accounts::load(&self.root).in_group(user, ADMIN_GROUP) },
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

    pub(crate) fn authenticator() -> (Authenticator, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("etc")).unwrap();
        std::fs::write(dir.path().join("etc/group"), "sudo:x:27:anna\n").unwrap();
        (Authenticator::new(Box::new(FakePam), SysRoot::new(dir.path())), dir)
    }

    #[test]
    fn outcomes() {
        let (a, _dir) = authenticator();
        let long = "k".repeat(MAX_PASSWORD_BYTES + 1);
        let cases = [
            ("anna", "kura", AuthOutcome::Ok { admin: true }),
            ("bob", "kura", AuthOutcome::Ok { admin: false }),
            ("bob", "nope", AuthOutcome::Wrong),
            ("old", "kura", AuthOutcome::Expired),
            ("Bad Name", "kura", AuthOutcome::Wrong),
            ("bob", "", AuthOutcome::Wrong),
            ("bob", "ku\0ra", AuthOutcome::Wrong),
            ("bob", long.as_str(), AuthOutcome::Wrong),
        ];
        for (user, password, want) in cases {
            assert_eq!(a.authenticate(user, password), want, "{user}");
        }
    }
}
