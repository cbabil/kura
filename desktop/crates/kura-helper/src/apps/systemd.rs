//! The real [`Apps`]: `kura-apps` as the transient unit
//! `kura-job-app.service`. Proven by the Linux CI jobs.

use std::time::Duration;

use kura_desktop_core::updates::JobState;

use super::Apps;
use crate::Fut;
use crate::job::JobUnit;

/// The root command, in the image.
const COMMAND: &str = "/usr/lib/kura/kura-apps";
/// Pulling a large image over a slow line takes a while; not for ever.
const JOB_TIMEOUT: Duration = Duration::from_secs(3600);

/// The catalog's jobs through the system bus.
pub struct SystemdApps {
    job: JobUnit,
}

impl SystemdApps {
    /// Uses `conn`, the helper's own connection to the system bus.
    ///
    /// # Errors
    /// Fails when a proxy cannot be set up.
    pub async fn new(conn: &zbus::Connection) -> zbus::Result<Self> {
        Ok(Self { job: JobUnit::new(conn, "kura-job-app.service", JOB_TIMEOUT).await? })
    }
}

impl Apps for SystemdApps {
    fn start(&self, args: Vec<String>) -> Fut<'_, Result<(), String>> {
        Box::pin(async move {
            let argv: Vec<String> = std::iter::once(COMMAND.to_owned()).chain(args).collect();
            self.job.start("Kura app catalog", vec![argv], &["PATH=/usr/sbin:/usr/bin:/sbin:/bin"]).await
        })
    }

    fn job_state(&self) -> Fut<'_, Option<JobState>> {
        Box::pin(self.job.state())
    }

    fn job_output(&self) -> Fut<'_, Vec<String>> {
        Box::pin(self.job.output())
    }
}
