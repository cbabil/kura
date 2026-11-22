//! The App Catalog (ADR-032): the templates Kura ships in
//! `/usr/lib/kura/catalog/<id>/`, which of them are installed in
//! `/srv/apps/<id>/`, and the three things an administrator may ask for.
//! The root command `kura-apps` does them and checks everything again.

#[cfg(test)]
mod tests;

use serde::{Deserialize, Serialize};

use crate::root::SysRoot;
use crate::updates::Job;

/// Where the templates are.
pub const CATALOG: &str = "/usr/lib/kura/catalog";
/// Where installed apps are.
pub const APPS: &str = "/srv/apps";
/// The lowest port an app may be given (below are the system's own).
pub const MIN_PORT: u16 = 1024;

/// A template's facts, as its `app.json` holds them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Template {
    pub id: String,
    pub name: String,
    /// The version of the app this Kura installs.
    pub version: String,
    /// The port proposed for its page.
    pub port: u16,
    /// Ports it also needs, which cannot be chosen (DNS, file sync).
    pub fixed_ports: Vec<u16>,
    /// Folders under its data folder the administrators fill themselves.
    #[serde(default)]
    pub shared: Vec<String>,
    pub homepage: String,
}

/// An installed app: the port chosen and the version installed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Installed {
    pub port: u16,
    pub version: String,
}

/// One app of the catalog, as `CatalogApp` in the interface.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct App {
    #[serde(flatten)]
    pub template: Template,
    pub installed: Option<Installed>,
}

/// `Catalog` in the interface: the apps and the last install, update or removal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Catalog {
    pub apps: Vec<App>,
    pub job: Option<Job>,
}

/// An app's name in the catalog: a lowercase letter, then letters, digits
/// and hyphens, 31 at most.
pub fn valid_app_id(id: &str) -> bool {
    let mut chars = id.chars();
    let first = chars.next().is_some_and(|c| c.is_ascii_lowercase());
    first && (2..=31).contains(&id.len()) && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// What `/srv/apps/<id>/.env` says, when the app is installed.
fn installed(root: &SysRoot, id: &str) -> Option<Installed> {
    let env = root.read(format!("{APPS}/{id}/.env")).ok()?;
    let value = |key: &str| env.lines().find_map(|l| l.strip_prefix(key));
    Some(Installed {
        port: value("KURA_PORT=")?.parse().ok()?,
        version: value("KURA_VERSION=").unwrap_or("").to_owned(),
    })
}

/// The catalog's apps by name, each with what is installed of it. A
/// template that cannot be read, or whose folder is not its id, is left out.
pub fn read_apps(root: &SysRoot) -> Vec<App> {
    let Ok(folders) = std::fs::read_dir(root.path(CATALOG)) else { return Vec::new() };
    let mut apps: Vec<App> = folders
        .flatten()
        .filter_map(|folder| {
            let id = folder.file_name().into_string().ok().filter(|id| valid_app_id(id))?;
            let facts = root.read(format!("{CATALOG}/{id}/app.json")).ok()?;
            let template: Template = serde_json::from_str(&facts).ok().filter(|t: &Template| t.id == id)?;
            Some(App { installed: installed(root, &id), template })
        })
        .collect();
    apps.sort_by_key(|a| a.template.name.to_lowercase());
    apps
}

/// One thing an administrator asks of the catalog.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "what", rename_all = "kebab-case", deny_unknown_fields)]
pub enum AppChange {
    Install {
        id: String,
        port: u16,
    },
    /// To the version this Kura ships.
    Update {
        id: String,
    },
    /// `data` also deletes what the app kept.
    Remove {
        id: String,
        data: bool,
    },
}

/// Why a change is refused before anything runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum InvalidAppChange {
    #[error("no such app in the catalog")]
    Unknown,
    #[error("already installed")]
    Installed,
    #[error("not installed")]
    NotInstalled,
    #[error("not a port from 1024 to 65535, or one another app has")]
    Port,
}

impl AppChange {
    /// The app the change is about.
    pub fn id(&self) -> &str {
        match self {
            Self::Install { id, .. } | Self::Update { id } | Self::Remove { id, .. } => id,
        }
    }

    /// "install", "update" or "remove", for the journal.
    pub fn name(&self) -> &'static str {
        match self {
            Self::Install { .. } => "install",
            Self::Update { .. } => "update",
            Self::Remove { .. } => "remove",
        }
    }

    /// The arguments of `kura-apps` for this change, given the catalog as
    /// it is now.
    ///
    /// # Errors
    /// An app that is not in the catalog, one installed twice or not at
    /// all, a port out of range or taken by another installed app.
    pub fn command(&self, apps: &[App]) -> Result<Vec<String>, InvalidAppChange> {
        let app = apps.iter().find(|a| a.template.id == self.id()).ok_or(InvalidAppChange::Unknown)?;
        let id = app.template.id.clone();
        match self {
            Self::Install { port, .. } => {
                if app.installed.is_some() {
                    return Err(InvalidAppChange::Installed);
                }
                let taken = |a: &App| {
                    a.installed.as_ref().is_some_and(|i| i.port == *port || a.template.fixed_ports.contains(port))
                };
                if *port < MIN_PORT || app.template.fixed_ports.contains(port) || apps.iter().any(taken) {
                    return Err(InvalidAppChange::Port);
                }
                Ok(vec!["install".into(), id, port.to_string()])
            }
            _ if app.installed.is_none() => Err(InvalidAppChange::NotInstalled),
            Self::Update { .. } => Ok(vec!["update".into(), id]),
            Self::Remove { data, .. } => {
                let mut args = vec!["remove".to_owned(), id];
                args.extend(data.then(|| "data".to_owned()));
                Ok(args)
            }
        }
    }
}
