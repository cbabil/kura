//! kura-helper: the root half of Kura Desktop (ADR-023). In D1 it answers one
//! D-Bus method, `io.kura.Helper.Authenticate(user, password)`, through PAM's
//! `login` service so expiry, locks and faillock behave as at the console.

pub mod authenticate;
pub mod iface;
#[cfg(target_os = "linux")]
pub mod pam;

pub use authenticate::{Authenticator, Pam, PamVerdict};
pub use iface::{BUS_NAME, HelperIface, OBJECT_PATH};
