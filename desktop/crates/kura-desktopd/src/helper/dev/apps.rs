//! The development stand-in for the App Catalog: the templates Kura ships,
//! and "jobs" that are done as soon as they start and only write or take
//! away the `.env` that says an app is installed. No container is started.

use std::path::PathBuf;
use std::sync::Mutex;

use kura_desktop_core::catalog::{APPS, CATALOG, Template};
use kura_desktop_core::lock;
use kura_desktop_core::updates::JobState;
use kura_helper::Fut;
use kura_helper::apps::Apps;

/// The facts of the shipped templates, from the repository itself.
const TEMPLATES: [&str; 6] = [
    include_str!("../../../../../../packages/os-desktop/catalog/adguard-home/app.json"),
    include_str!("../../../../../../packages/os-desktop/catalog/gitea/app.json"),
    include_str!("../../../../../../packages/os-desktop/catalog/home-assistant/app.json"),
    include_str!("../../../../../../packages/os-desktop/catalog/jellyfin/app.json"),
    include_str!("../../../../../../packages/os-desktop/catalog/syncthing/app.json"),
    include_str!("../../../../../../packages/os-desktop/catalog/uptime-kuma/app.json"),
];

/// Applies the catalog's changes to the files under `root`.
pub struct DevApps {
    root: PathBuf,
    /// What the last job was asked.
    last: Mutex<Option<Vec<String>>>,
}

impl DevApps {
    /// Puts the catalog under `root`, with Gitea installed in an older
    /// version so an update shows.
    ///
    /// # Errors
    /// Fails when the files cannot be written.
    pub fn new(root: PathBuf) -> std::io::Result<Self> {
        let apps = Self { root, last: Mutex::new(None) };
        for facts in TEMPLATES {
            let template: Template = serde_json::from_str(facts)?;
            let folder = apps.at(CATALOG).join(&template.id);
            std::fs::create_dir_all(&folder)?;
            std::fs::write(folder.join("app.json"), facts)?;
        }
        apps.write_env("gitea", "3003", "1.22.0")?;
        Ok(apps)
    }

    fn at(&self, device: &str) -> PathBuf {
        self.root.join(device.trim_start_matches('/'))
    }

    fn write_env(&self, id: &str, port: &str, version: &str) -> std::io::Result<()> {
        let folder = self.at(APPS).join(id);
        std::fs::create_dir_all(&folder)?;
        std::fs::write(folder.join(".env"), format!("KURA_PORT={port}\nKURA_VERSION={version}\n"))
    }

    fn apply(&self, args: &[String]) -> std::io::Result<()> {
        let (what, id) = (args.first().map_or("", String::as_str), args.get(1).map_or("", String::as_str));
        let env = self.at(APPS).join(id).join(".env");
        let shipped = || -> std::io::Result<String> {
            let facts = std::fs::read_to_string(self.at(CATALOG).join(id).join("app.json"))?;
            Ok(serde_json::from_str::<Template>(&facts)?.version)
        };
        match what {
            "install" => self.write_env(id, args.get(2).map_or("", String::as_str), &shipped()?),
            "update" => {
                let old = std::fs::read_to_string(&env)?;
                let port = old.lines().find_map(|l| l.strip_prefix("KURA_PORT=")).unwrap_or("");
                self.write_env(id, port, &shipped()?)
            }
            _ => std::fs::remove_file(env),
        }
    }
}

impl Apps for DevApps {
    fn start(&self, args: Vec<String>) -> Fut<'_, Result<(), String>> {
        let done = self.apply(&args).map_err(|e| e.to_string());
        *lock(&self.last) = Some(args);
        Box::pin(async move { done })
    }

    fn job_state(&self) -> Fut<'_, Option<JobState>> {
        let ran = lock(&self.last).is_some();
        Box::pin(async move { ran.then_some(JobState::Done) })
    }

    fn job_output(&self) -> Fut<'_, Vec<String>> {
        let lines = lock(&self.last).as_ref().map(|args| {
            vec![format!("kura-apps {}", args.join(" ")), "Done (development: nothing was started).".to_owned()]
        });
        Box::pin(async move { lines.unwrap_or_default() })
    }
}
