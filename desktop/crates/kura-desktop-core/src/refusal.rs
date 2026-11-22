//! The names of the helper's refusals on D-Bus, shared by the helper (which
//! sends them as errors `io.kura.Helper1.Error.<Name>`) and desktopd (which
//! reads them). The helper's own names cannot be mistaken for the bus's
//! errors, such as a policy that denies the call.

/// What every refusal's D-Bus error name starts with.
pub const ERROR_PREFIX: &str = "io.kura.Helper1.Error.";

/// Why the helper refused an action.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refused {
    /// No live ticket: the user must sign in (again).
    SignedOut,
    /// Only an administrator (a member of `sudo`) may do this.
    Admin,
    /// A value outside what the action accepts.
    Invalid,
    /// No such container or terminal.
    NotFound,
    /// The user's account has no login shell.
    NoShell,
    /// Too many at once.
    Busy,
    /// Docker, the journal or systemd did not answer.
    Unavailable,
}

impl Refused {
    /// Every refusal.
    pub const ALL: [Self; 7] =
        [Self::SignedOut, Self::Admin, Self::Invalid, Self::NotFound, Self::NoShell, Self::Busy, Self::Unavailable];

    /// The last part of the D-Bus error name.
    pub fn name(self) -> &'static str {
        match self {
            Self::SignedOut => "SignedOut",
            Self::Admin => "Admin",
            Self::Invalid => "Invalid",
            Self::NotFound => "NotFound",
            Self::NoShell => "NoShell",
            Self::Busy => "Busy",
            Self::Unavailable => "Unavailable",
        }
    }

    /// Reads a full D-Bus error name; `None` for any error that is not one
    /// of the helper's refusals.
    pub fn from_error_name(name: &str) -> Option<Self> {
        let last = name.strip_prefix(ERROR_PREFIX)?;
        Self::ALL.into_iter().find(|r| r.name() == last)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip_and_the_buses_own_errors_are_not_refusals() {
        for r in Refused::ALL {
            assert_eq!(Refused::from_error_name(&format!("{ERROR_PREFIX}{}", r.name())), Some(r));
        }
        for other in ["org.freedesktop.DBus.Error.AccessDenied", "io.kura.Helper1.Error.Nope", "Admin", ""] {
            assert_eq!(Refused::from_error_name(other), None, "{other}");
        }
    }
}
