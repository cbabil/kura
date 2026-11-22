//! What Settings needs of the system (ADR-029): the network devices and the
//! clock, read with `nmcli` and `timedatectl`, and changes made by the root
//! command `kura-settings`, run as a systemd unit of its own so it is
//! outside the helper's sandbox ([`systemd::SystemdSystem`]).

#[cfg(target_os = "linux")]
pub mod systemd;

use kura_desktop_core::settings::Command;

use crate::Fut;

/// What the helper asks of the system for Settings.
pub trait System: Send + Sync {
    /// The output of `nmcli -t -f … device show`; empty when it fails.
    fn devices(&self) -> Fut<'_, String>;
    /// The output of `timedatectl show -p Timezone -p NTP -p NTPSynchronized`.
    fn clock(&self) -> Fut<'_, String>;
    /// Runs `kura-settings` with a checked command and waits for it; the
    /// error is what the command said.
    fn change(&self, command: Command) -> Fut<'_, Result<(), String>>;
}
