//! The answer of `io.kura.Helper1.Authenticate`, shared by the helper (which
//! sends it over D-Bus as `(ok, reason, admin)`) and desktopd (which reads it).

/// The `reason` for a refused password.
pub const REASON_WRONG: &str = "wrong";
/// The `reason` for a password that must be changed first.
pub const REASON_EXPIRED: &str = "expired";

/// The result of checking a user name and password.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthOutcome {
    /// The password is right; `admin` is membership of `sudo`.
    Ok { admin: bool },
    /// Wrong user name or password, or any refusal not worth telling apart.
    Wrong,
    /// The password is right but must be changed at the console or over SSH.
    Expired,
}

impl AuthOutcome {
    /// Encodes the outcome as the D-Bus reply `(ok, reason, admin)`.
    pub fn to_wire(self) -> (bool, String, bool) {
        match self {
            Self::Ok { admin } => (true, String::new(), admin),
            Self::Wrong => (false, REASON_WRONG.to_owned(), false),
            Self::Expired => (false, REASON_EXPIRED.to_owned(), false),
        }
    }

    /// Decodes a D-Bus reply; an unknown reason reads as [`AuthOutcome::Wrong`].
    pub fn from_wire(ok: bool, reason: &str, admin: bool) -> Self {
        match (ok, reason) {
            (true, _) => Self::Ok { admin },
            (false, REASON_EXPIRED) => Self::Expired,
            _ => Self::Wrong,
        }
    }
}

/// True for a plausible Debian user name (`NAME_REGEX`, at most 32 bytes).
/// Anything else is refused before PAM sees it.
pub fn valid_user_name(name: &str) -> bool {
    let mut chars = name.chars();
    let first_ok = chars.next().is_some_and(|c| c.is_ascii_lowercase() || c == '_');
    first_ok && name.len() <= 32 && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

/// The longest password passed on, in bytes; longer ones are refused.
pub const MAX_PASSWORD_BYTES: usize = 512;

/// True when a sign-in is worth asking PAM about: a valid user name and a
/// non-empty password of at most [`MAX_PASSWORD_BYTES`] without NUL bytes.
/// desktopd and the helper both apply it, so neither trusts the other.
pub fn well_formed(user: &str, password: &str) -> bool {
    valid_user_name(user) && !password.is_empty() && password.len() <= MAX_PASSWORD_BYTES && !password.contains('\0')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_round_trip() {
        for o in [
            AuthOutcome::Ok { admin: true },
            AuthOutcome::Ok { admin: false },
            AuthOutcome::Wrong,
            AuthOutcome::Expired,
        ] {
            let (ok, reason, admin) = o.to_wire();
            assert_eq!(AuthOutcome::from_wire(ok, &reason, admin), o);
        }
        assert_eq!(AuthOutcome::from_wire(false, "locked", true), AuthOutcome::Wrong);
    }

    #[test]
    fn well_formed_sign_ins() {
        let long = "k".repeat(MAX_PASSWORD_BYTES + 1);
        let cases = [
            ("kura", "pw", true),
            ("Bad Name", "pw", false),
            ("kura", "", false),
            ("kura", "p\0w", false),
            ("kura", long.as_str(), false),
            ("kura", &long[1..], true),
        ];
        for (user, password, want) in cases {
            assert_eq!(well_formed(user, password), want, "{user} {}", password.len());
        }
    }

    #[test]
    fn user_names() {
        let cases = [
            ("kura", true),
            ("_svc", true),
            ("a-b_1", true),
            ("", false),
            ("Root", false),
            ("1abc", false),
            ("a b", false),
            ("a:b", false),
            (&"a".repeat(33), false),
        ];
        for (name, want) in cases {
            assert_eq!(valid_user_name(name), want, "{name:?}");
        }
    }
}
