//! The machine itself: switching it off, and Kura's updates. The helper
//! only asks: logind restarts or powers off, and an update runs as a
//! systemd unit of its own (`kura-job-update.service`), outside the
//! helper's sandbox and alive across the helper's own restart during an
//! upgrade ([`systemd::SystemdMachine`]).

#[cfg(target_os = "linux")]
pub mod systemd;

use kura_desktop_core::actions::{PowerKind, UpdateKind};
use kura_desktop_core::updates::JobState;

use crate::Fut;

/// The command lines of an update job; nothing in them comes from a request.
///
/// - A list that cannot be fetched is an error, not "up to date".
/// - Nobody is there to answer dpkg about a changed configuration file, so
///   the package's default is taken and, where there is none, the file on
///   the device is kept (what unattended-upgrades does too).
/// - `--yes` also accepts removals a full upgrade needs; the documented
///   manual command would list them first.
pub fn update_commands(what: UpdateKind) -> Vec<Vec<&'static str>> {
    const APT: &str = "/usr/bin/apt-get";
    let refresh = vec![APT, "update", "-o", "APT::Update::Error-Mode=any"];
    let upgrade = vec![
        APT,
        "--yes",
        "-o",
        "Dpkg::Options::=--force-confdef",
        "-o",
        "Dpkg::Options::=--force-confold",
        "full-upgrade",
    ];
    match what {
        UpdateKind::Check => vec![refresh],
        // The same as the documented `apt update && apt full-upgrade`.
        UpdateKind::Install => vec![refresh, upgrade],
    }
}

/// What the helper asks of the machine.
pub trait Machine: Send + Sync {
    /// Restarts or shuts down, as `systemctl reboot` or `poweroff` would.
    fn power(&self, how: PowerKind) -> Fut<'_, Result<(), String>>;
    /// The output of `apt-cache policy kura`; empty when apt cannot say.
    fn apt_policy(&self) -> Fut<'_, String>;
    /// Starts an update job, replacing the record of the last one; an
    /// error when it cannot start. The caller makes sure none is running.
    fn start_update(&self, what: UpdateKind) -> Fut<'_, Result<(), String>>;
    /// How far the last update job is, if one ran.
    fn job_state(&self) -> Fut<'_, Option<JobState>>;
    /// The last lines the last update job wrote, cleaned for showing.
    fn job_output(&self) -> Fut<'_, Vec<String>>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_update_is_fixed_apt_commands_that_ask_nobody() {
        let check = update_commands(UpdateKind::Check);
        assert_eq!(check, [["/usr/bin/apt-get", "update", "-o", "APT::Update::Error-Mode=any"]]);
        let install = update_commands(UpdateKind::Install);
        assert_eq!((install.len(), &install[0]), (2, &check[0]));
        assert_eq!(install[1].last(), Some(&"full-upgrade"));
        for option in ["--yes", "Dpkg::Options::=--force-confdef", "Dpkg::Options::=--force-confold"] {
            assert!(install[1].contains(&option), "{option}");
        }
        assert!(install.iter().flatten().all(|arg| !arg.contains("reboot") && !arg.contains("autoremove")));
    }
}
