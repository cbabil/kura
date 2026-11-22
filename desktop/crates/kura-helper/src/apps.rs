//! The App Catalog's jobs (ADR-032): installing, updating or removing an
//! app is the root command `kura-apps`, run as a systemd unit of its own
//! (`kura-job-app.service`), one at a time, as updates are. The helper only
//! asks; the command's output is the unit's journal.

#[cfg(target_os = "linux")]
pub mod systemd;

use kura_desktop_core::updates::JobState;

use crate::Fut;

/// What the helper asks for the catalog.
pub trait Apps: Send + Sync {
    /// Starts `kura-apps` with `args` (already checked), replacing the
    /// record of the last job. The caller makes sure none is running.
    fn start(&self, args: Vec<String>) -> Fut<'_, Result<(), String>>;
    /// How far the last job is, if one ran.
    fn job_state(&self) -> Fut<'_, Option<JobState>>;
    /// The last lines the last job wrote, cleaned for showing.
    fn job_output(&self) -> Fut<'_, Vec<String>>;
}
