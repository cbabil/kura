//! kura-helper: the root half of Kura Desktop (ADR-023, ADR-027). It serves
//! `io.kura.Helper1` on the system bus to `kura-desktopd` only, and does a
//! fixed list of things ([`policy::Action`]):
//!
//! - checks a password through PAM's `login` service (five wrong ones a
//!   minute per user at most), and gives a ticket that every other method
//!   needs;
//! - starts a login shell for the signed-in user on a pseudo-terminal;
//! - lists, starts, stops and restarts Docker containers, and reads their
//!   logs;
//! - reads the system journal;
//! - says whether a Kura update waits, starts one as a job of its own, and
//!   restarts or shuts down the machine;
//! - shows and changes the settings: host name, network, clock, users;
//! - starts each person's Browser as them and hands over its screen.

pub mod apps;
pub mod authenticate;
pub mod browser;
pub mod docker;
#[cfg(any(test, feature = "fakes"))]
pub mod fakes;
pub mod iface;
#[cfg(target_os = "linux")]
pub mod job;
pub mod journal;
pub mod machine;
#[cfg(target_os = "linux")]
pub mod pam;
pub mod policy;
pub mod refusal;
pub mod service;
pub mod system;
#[cfg(target_os = "linux")]
pub mod systemd;
pub mod terminal;

pub use authenticate::{Authenticator, Pam, PamVerdict};
pub use iface::{BUS_NAME, HelperIface, OBJECT_PATH};
pub use service::{Backends, Service};

/// The boxed future the helper's traits return.
pub type Fut<'a, T> = std::pin::Pin<Box<dyn Future<Output = T> + Send + 'a>>;
