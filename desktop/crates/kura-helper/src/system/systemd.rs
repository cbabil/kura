//! The real [`System`]: `nmcli` and `timedatectl` for reading, and for a
//! change a transient unit `kura-job-settings-<id>.service` running
//! `/usr/lib/kura/kura-settings`. A password is handed over in a file only
//! root can read, in the helper's own runtime folder, which the command
//! removes once read. Proven by the Linux CI jobs.

use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::time::Duration;

use kura_desktop_core::session::new_session_id;
use kura_desktop_core::settings::Command;
use zbus::Variant as Value;

use super::System;
use crate::Fut;
use crate::journal::JOURNALCTL;
use crate::machine::systemd::output_of;
use crate::systemd::{ManagerProxy, Property};

/// The root command behind Settings.
const SETTINGS: &str = "/usr/lib/kura/kura-settings";
/// The helper's runtime folder (`RuntimeDirectory=` in its unit), mode 0700.
const SECRETS: &str = "/run/kura-helper";
/// How long a change may take.
const TIMEOUT: Duration = Duration::from_secs(60);
const POLL: Duration = Duration::from_millis(150);
/// The device fields Settings shows.
const DEVICE_FIELDS: &str =
    "GENERAL.DEVICE,GENERAL.TYPE,GENERAL.HWADDR,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS";

/// The system through the system bus.
pub struct SystemdSystem {
    conn: zbus::Connection,
    manager: ManagerProxy<'static>,
}

impl SystemdSystem {
    /// Uses `conn`, the helper's own connection to the system bus.
    ///
    /// # Errors
    /// Fails when the proxy cannot be set up.
    pub async fn new(conn: &zbus::Connection) -> zbus::Result<Self> {
        Ok(Self { conn: conn.clone(), manager: ManagerProxy::new(conn).await? })
    }

    /// Writes `secret` to a new file only root can read; its path.
    fn hand_over(secret: &str) -> std::io::Result<PathBuf> {
        let path = PathBuf::from(SECRETS).join(new_session_id());
        let mut file = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path)?;
        if let Err(e) = file.write_all(secret.as_bytes()) {
            let _ = std::fs::remove_file(&path);
            return Err(e);
        }
        Ok(path)
    }

    /// The unit's `ActiveState`, or `None` once systemd has collected it.
    async fn state(&self, unit: &str) -> Option<String> {
        crate::systemd::unit(&self.conn, &self.manager, unit).await?.active_state().await.ok()
    }

    async fn run(&self, command: Command) -> Result<(), String> {
        let unit = format!("kura-job-settings-{}.service", &new_session_id()[..16]);
        let mut argv = vec![SETTINGS.to_owned()];
        argv.extend(command.args);
        let secret = match &command.secret {
            Some(secret) => Some(Self::hand_over(secret).map_err(|e| format!("secret file: {e}"))?),
            None => None,
        };
        if let Some(path) = &secret {
            argv.extend(["--secret-file".to_owned(), path.display().to_string()]);
        }
        let properties: Vec<Property<'_>> = vec![
            ("Description", Value::from("Kura settings change")),
            ("Type", Value::from("oneshot")),
            // Kept once it has ended, so "done" is seen and not guessed from
            // a unit that is not there (which is also how one looks before
            // systemd has started it).
            ("RemainAfterExit", Value::from(true)),
            ("TimeoutStartUSec", Value::from(TIMEOUT.as_micros() as u64)),
            ("Environment", Value::from(vec!["PATH=/usr/sbin:/usr/bin:/sbin:/bin"])),
            ("ExecStart", Value::from(vec![(SETTINGS.to_owned(), argv, false)])),
        ];
        let started = self.manager.start_transient_unit(&unit, "fail", &properties, &[]).await;
        let outcome = match started {
            Ok(_) => self.finished(&unit).await,
            Err(e) => Err(format!("systemd: {e}")),
        };
        // The command removes the file once read; this is for when it never ran.
        if let Some(path) = secret {
            let _ = std::fs::remove_file(path);
        }
        outcome
    }

    /// Waits for the unit to end: "active" is the command having succeeded
    /// (the unit is kept, then stopped here), "failed" gives its last line.
    async fn finished(&self, unit: &str) -> Result<(), String> {
        let deadline = tokio::time::Instant::now() + TIMEOUT;
        loop {
            match self.state(unit).await.as_deref() {
                Some("active") => {
                    let _ = self.manager.stop_unit(unit, "replace").await;
                    return Ok(());
                }
                Some("failed") => {
                    // The command's own lines, not systemd's about the unit.
                    let own = format!("_SYSTEMD_UNIT={unit}");
                    let said =
                        output_of(JOURNALCTL, &["--output=cat", "--no-pager", "--quiet", "--lines=1", &own]).await;
                    let _ = self.manager.reset_failed_unit(unit).await;
                    return Err(said.trim().to_owned());
                }
                _ if tokio::time::Instant::now() >= deadline => {
                    let _ = self.manager.stop_unit(unit, "replace").await;
                    return Err("the change took too long".into());
                }
                _ => tokio::time::sleep(POLL).await,
            }
        }
    }
}

impl System for SystemdSystem {
    fn devices(&self) -> Fut<'_, String> {
        Box::pin(output_of("/usr/bin/nmcli", &["-t", "-f", DEVICE_FIELDS, "device", "show"]))
    }

    fn clock(&self) -> Fut<'_, String> {
        Box::pin(output_of("/usr/bin/timedatectl", &["show", "-p", "Timezone", "-p", "NTP", "-p", "NTPSynchronized"]))
    }

    fn change(&self, command: Command) -> Fut<'_, Result<(), String>> {
        Box::pin(self.run(command))
    }
}
