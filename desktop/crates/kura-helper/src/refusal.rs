//! Why the helper refused an action, and the D-Bus error each refusal
//! travels as: `io.kura.Helper1.Error.<Name>`, the names of
//! [`kura_desktop_core::refusal::Refused`], which desktopd maps to HTTP
//! statuses. They are the helper's own, so desktopd cannot mistake one of
//! the bus's errors for them.

use kura_desktop_core::refusal::Refused;

/// A refused action.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Refusal {
    /// No live ticket: the user must sign in (again).
    #[error("not signed in")]
    SignedOut,
    /// Only an administrator (a member of `sudo`) may do this.
    #[error("administrators only")]
    Admin,
    /// A value outside what the action accepts.
    #[error("invalid: {0}")]
    Invalid(String),
    /// No such container or terminal.
    #[error("not found")]
    NotFound,
    /// The user's account has no login shell.
    #[error("no login shell")]
    NoShell,
    /// Too many at once.
    #[error("too many")]
    Busy,
    /// Docker, the journal or systemd did not answer.
    #[error("unavailable: {0}")]
    Unavailable(String),
}

impl Refusal {
    /// The refusal's name on the wire.
    pub fn kind(&self) -> Refused {
        match self {
            Self::SignedOut => Refused::SignedOut,
            Self::Admin => Refused::Admin,
            Self::Invalid(_) => Refused::Invalid,
            Self::NotFound => Refused::NotFound,
            Self::NoShell => Refused::NoShell,
            Self::Busy => Refused::Busy,
            Self::Unavailable(_) => Refused::Unavailable,
        }
    }
}

impl From<crate::docker::DockerError> for Refusal {
    fn from(e: crate::docker::DockerError) -> Self {
        match e {
            crate::docker::DockerError::NotFound => Self::NotFound,
            crate::docker::DockerError::Unavailable(why) => Self::Unavailable(why),
        }
    }
}

/// The errors of `io.kura.Helper1`. The variant names are the wire names,
/// so they must stay those of [`Refused`] (a test checks it).
#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "io.kura.Helper1.Error")]
pub enum HelperError {
    #[zbus(error)]
    ZBus(zbus::Error),
    SignedOut(String),
    Admin(String),
    Invalid(String),
    NotFound(String),
    NoShell(String),
    Busy(String),
    Unavailable(String),
    /// The caller is not kura-desktopd.
    Caller(String),
}

impl From<Refusal> for HelperError {
    fn from(refusal: Refusal) -> Self {
        let text = refusal.to_string();
        match refusal.kind() {
            Refused::SignedOut => Self::SignedOut(text),
            Refused::Admin => Self::Admin(text),
            Refused::Invalid => Self::Invalid(text),
            Refused::NotFound => Self::NotFound(text),
            Refused::NoShell => Self::NoShell(text),
            Refused::Busy => Self::Busy(text),
            Refused::Unavailable => Self::Unavailable(text),
        }
    }
}

#[cfg(test)]
mod tests {
    use kura_desktop_core::refusal::ERROR_PREFIX;
    use zbus::DBusError;

    use super::*;

    #[test]
    fn each_refusal_travels_under_its_own_name() {
        let all = [
            Refusal::SignedOut,
            Refusal::Admin,
            Refusal::Invalid("x".into()),
            Refusal::NotFound,
            Refusal::NoShell,
            Refusal::Busy,
            Refusal::Unavailable("x".into()),
        ];
        assert_eq!(all.len(), Refused::ALL.len());
        for refusal in all {
            let kind = refusal.kind();
            let name = HelperError::from(refusal).name().to_string();
            assert_eq!(name, format!("{ERROR_PREFIX}{}", kind.name()));
            assert_eq!(Refused::from_error_name(&name), Some(kind));
        }
        let caller = HelperError::Caller("x".into()).name().to_string();
        assert_eq!(Refused::from_error_name(&caller), None, "not a refusal desktopd acts on");
    }
}
