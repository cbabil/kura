//! A root job as a transient systemd unit of a fixed name: one at a time,
//! kept after it ends so its outcome can be shown, its output read from the
//! journal. Updates and the App Catalog each have one. Nothing in a job's
//! command lines comes unchecked from a request.

use std::time::Duration;

use kura_desktop_core::containers::{MAX_LINE_BYTES, clean, cut};
use kura_desktop_core::updates::{JobState, MAX_OUTPUT_LINES};
use zbus::Variant as Value;

use crate::journal::JOURNALCTL;
use crate::machine::systemd::output_of;
use crate::systemd::{ManagerProxy, Property, UnitProxy};

/// One named job unit.
pub struct JobUnit {
    conn: zbus::Connection,
    manager: ManagerProxy<'static>,
    unit: &'static str,
    /// A job that has not finished by then is stopped, so the next can start.
    timeout: Duration,
}

impl JobUnit {
    /// The job called `unit`, through `conn`.
    ///
    /// # Errors
    /// Fails when the proxy cannot be set up.
    pub async fn new(conn: &zbus::Connection, unit: &'static str, timeout: Duration) -> zbus::Result<Self> {
        Ok(Self { conn: conn.clone(), manager: ManagerProxy::new(conn).await?, unit, timeout })
    }

    /// The unit, or `None` when systemd has no such unit.
    async fn proxy(&self) -> Option<UnitProxy<'static>> {
        crate::systemd::unit(&self.conn, &self.manager, self.unit).await
    }

    /// Runs `commands` one after the other with the environment `env`.
    ///
    /// # Errors
    /// Fails when systemd does not start the unit.
    pub async fn start(&self, description: &str, commands: Vec<Vec<String>>, env: &[&str]) -> Result<(), String> {
        // The last run's unit stays to tell how it ended; make room for this one.
        if self.proxy().await.is_some() {
            let _ = self.manager.stop_unit(self.unit, "replace").await;
            let _ = self.manager.reset_failed_unit(self.unit).await;
        }
        let commands: Vec<(String, Vec<String>, bool)> =
            commands.into_iter().filter(|argv| !argv.is_empty()).map(|argv| (argv[0].clone(), argv, false)).collect();
        let properties = || -> Vec<Property<'_>> {
            vec![
                ("Description", Value::from(description)),
                ("Type", Value::from("oneshot")),
                // Kept after it ends, so the desktop can show whether it worked.
                ("RemainAfterExit", Value::from(true)),
                ("TimeoutStartUSec", Value::from(self.timeout.as_micros() as u64)),
                ("Environment", Value::from(env.to_vec())),
                ("ExecStart", Value::from(commands.clone())),
            ]
        };
        // The old unit may take a moment to go: once more before giving up.
        for wait in [Duration::ZERO, Duration::from_secs(1)] {
            tokio::time::sleep(wait).await;
            match self.manager.start_transient_unit(self.unit, "fail", &properties(), &[]).await {
                Ok(_) => return Ok(()),
                Err(e) if wait.is_zero() => tracing::debug!("starting {}: {e}", self.unit),
                Err(e) => return Err(e.to_string()),
            }
        }
        Err("the job did not start".into())
    }

    /// How far the last run is, if one ran.
    pub async fn state(&self) -> Option<JobState> {
        match self.proxy().await?.active_state().await.ok()?.as_str() {
            "activating" | "deactivating" => Some(JobState::Running),
            "active" => Some(JobState::Done),
            "failed" => Some(JobState::Failed),
            _ => None,
        }
    }

    /// The last lines the last run wrote, cleaned for showing.
    pub async fn output(&self) -> Vec<String> {
        // This run's lines only: the journal keeps earlier runs of the unit too.
        let Some(id) = async { self.proxy().await?.invocation_id().await.ok() }.await else { return Vec::new() };
        let run = format!("_SYSTEMD_INVOCATION_ID={}", id.iter().map(|b| format!("{b:02x}")).collect::<String>());
        let lines = format!("--lines={MAX_OUTPUT_LINES}");
        let text = output_of(JOURNALCTL, &["--output=cat", "--no-pager", "--quiet", &lines, &run]).await;
        text.lines().map(|line| cut(&clean(line), MAX_LINE_BYTES)).collect()
    }
}
