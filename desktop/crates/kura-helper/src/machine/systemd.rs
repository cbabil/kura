//! The real [`Machine`]: logind for power, apt-cache for the waiting
//! version, and a job unit ([`JobUnit`]) for the update. Proven by the Linux CI jobs.

use std::process::Stdio;
use std::time::Duration;

use kura_desktop_core::actions::{PowerKind, UpdateKind};
use kura_desktop_core::updates::{JobState, PACKAGE};

use super::{Machine, update_commands};
use crate::Fut;
use crate::job::JobUnit;
use crate::systemd::ManagerProxy;

/// The update job's unit: one at a time.
const UNIT: &str = "kura-job-update.service";
/// A job that has not finished by then is stopped, so the next can start.
const JOB_TIMEOUT: Duration = Duration::from_secs(3 * 3600);

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait Login {
    fn reboot(&self, interactive: bool) -> zbus::Result<()>;
    fn power_off(&self, interactive: bool) -> zbus::Result<()>;
}

/// The machine through the system bus.
pub struct SystemdMachine {
    login: LoginProxy<'static>,
    manager: ManagerProxy<'static>,
    job: JobUnit,
}

/// Runs a fixed program with an empty environment and gives its output;
/// empty when it fails or takes more than 10 s.
pub(crate) async fn output_of(program: &str, args: &[&str]) -> String {
    let run = tokio::process::Command::new(program)
        .args(args)
        .env_clear()
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .output();
    match tokio::time::timeout(Duration::from_secs(10), run).await {
        Ok(Ok(out)) => String::from_utf8_lossy(&out.stdout).into_owned(),
        _ => String::new(),
    }
}

impl SystemdMachine {
    /// Uses `conn`, the helper's own connection to the system bus.
    ///
    /// # Errors
    /// Fails when a proxy cannot be set up.
    pub async fn new(conn: &zbus::Connection) -> zbus::Result<Self> {
        Ok(Self {
            login: LoginProxy::new(conn).await?,
            manager: ManagerProxy::new(conn).await?,
            job: JobUnit::new(conn, UNIT, JOB_TIMEOUT).await?,
        })
    }
}

impl Machine for SystemdMachine {
    fn power(&self, how: PowerKind) -> Fut<'_, Result<(), String>> {
        Box::pin(async move {
            let asked = match how {
                PowerKind::Restart => self.login.reboot(false).await,
                PowerKind::Shutdown => self.login.power_off(false).await,
            };
            asked.map_err(|e| e.to_string())
        })
    }

    fn apt_policy(&self) -> Fut<'_, String> {
        Box::pin(output_of("/usr/bin/apt-cache", &["policy", PACKAGE]))
    }

    fn start_update(&self, what: UpdateKind) -> Fut<'_, Result<(), String>> {
        Box::pin(async move {
            let commands = update_commands(what).into_iter().map(|argv| argv.into_iter().map(String::from).collect());
            let env = ["DEBIAN_FRONTEND=noninteractive", "PATH=/usr/sbin:/usr/bin:/sbin:/bin"];
            self.job.start("Kura update", commands.collect(), &env).await
        })
    }

    fn job_state(&self) -> Fut<'_, Option<JobState>> {
        Box::pin(self.job.state())
    }

    fn job_output(&self) -> Fut<'_, Vec<String>> {
        Box::pin(self.job.output())
    }

    fn browser(&self, on: bool) -> Fut<'_, Result<(), String>> {
        Box::pin(async move {
            let unit = kura_desktop_core::browser::UNIT;
            let asked = if on {
                self.manager.start_unit(unit, "replace").await
            } else {
                self.manager.stop_unit(unit, "replace").await
            };
            asked.map(|_| ()).map_err(|e| e.to_string())
        })
    }
}
