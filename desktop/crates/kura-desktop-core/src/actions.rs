//! Everything the helper does for a signed-in user: the fixed list, each
//! action's name on the wire, who may do it, and the arguments it takes.
//! desktopd builds a request from these and the helper reads it with them,
//! so both sides agree by construction. Nothing outside this list exists.

use serde::{Deserialize, Serialize};

use crate::containers::ContainerAction;

/// One thing the helper does. All but [`Action::Terminal`] and
/// [`Action::Files`] go through the
/// helper's `Ask` method by name, with JSON arguments.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// A shell as the user themself (its own D-Bus method: it returns a
    /// file descriptor).
    Terminal,
    /// The user's file agent, a program run as the user themself (its own
    /// D-Bus method too).
    Files,
    ListContainers,
    /// Start, stop or restart a container: [`ContainerArgs`].
    ControlContainer,
    /// [`LogsArgs`].
    ContainerLogs,
    /// [`JournalArgs`].
    ReadJournal,
    /// The installed and the waiting version, and the update job.
    UpdateStatus,
    /// Refresh the package lists or install what waits: [`UpdateArgs`].
    StartUpdate,
    /// Restart or shut down the machine: [`PowerArgs`].
    Power,
    /// Everything Settings shows.
    ReadSettings,
    /// One change to a setting: `settings::Change`.
    ChangeSetting,
    /// One's own password: [`OwnPasswordArgs`].
    ChangeOwnPassword,
    /// The App Catalog: the apps Kura ships and which are installed.
    ReadCatalog,
    /// Install, update or remove one of them: `catalog::AppChange`.
    ChangeApp,
    /// Start the shared Browser (ADR-036), if it is not running yet.
    Browser,
    /// Quit the shared Browser.
    BrowserStop,
}

impl Action {
    /// Every action.
    pub const ALL: [Self; 16] = [
        Self::Terminal,
        Self::Files,
        Self::ListContainers,
        Self::ControlContainer,
        Self::ContainerLogs,
        Self::ReadJournal,
        Self::UpdateStatus,
        Self::StartUpdate,
        Self::Power,
        Self::ReadSettings,
        Self::ChangeSetting,
        Self::ChangeOwnPassword,
        Self::ReadCatalog,
        Self::ChangeApp,
        Self::Browser,
        Self::BrowserStop,
    ];

    /// The action's name on the wire and in the journal.
    pub fn name(self) -> &'static str {
        match self {
            Self::Terminal => "terminal",
            Self::Files => "files",
            Self::ListContainers => "list-containers",
            Self::ControlContainer => "control-container",
            Self::ContainerLogs => "container-logs",
            Self::ReadJournal => "read-journal",
            Self::UpdateStatus => "update-status",
            Self::StartUpdate => "start-update",
            Self::Power => "power",
            Self::ReadSettings => "read-settings",
            Self::ChangeSetting => "change-setting",
            Self::ChangeOwnPassword => "change-own-password",
            Self::ReadCatalog => "read-catalog",
            Self::ChangeApp => "change-app",
            Self::Browser => "browser",
            Self::BrowserStop => "browser-stop",
        }
    }

    /// Reads a name; anything not on the list is `None`.
    pub fn parse(name: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|a| a.name() == name)
    }

    /// True for what only members of `sudo` may do. A person's own shell,
    /// files and password, the list of containers, whether an update waits
    /// and the shared Browser are open to every signed-in user.
    pub fn needs_admin(self) -> bool {
        !matches!(
            self,
            Self::Terminal
                | Self::Files
                | Self::ListContainers
                | Self::UpdateStatus
                | Self::ChangeOwnPassword
                | Self::Browser
                | Self::BrowserStop
        )
    }
}

/// Arguments of [`Action::ControlContainer`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContainerArgs {
    pub id: String,
    pub action: ContainerAction,
}

/// Arguments of [`Action::ChangeOwnPassword`]: the current password proves
/// it is the user, not just their open browser.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OwnPasswordArgs {
    pub current: String,
    pub password: String,
}

/// Arguments of [`Action::ContainerLogs`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LogsArgs {
    pub id: String,
    pub lines: u32,
}

/// Arguments of [`Action::ReadJournal`], as the interface sends them; the
/// helper checks them (`JournalQuery::new`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JournalArgs {
    pub lines: u32,
    /// "" for every unit.
    pub unit: String,
    /// -1 for every priority.
    pub priority: i32,
    /// "" or the cursor of the last entry already shown.
    pub after: String,
}

/// What an update job does.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum UpdateKind {
    /// Refresh the package lists, so a new version shows.
    Check,
    /// Install everything that waits. Never restarts the machine.
    Install,
}

/// Arguments of [`Action::StartUpdate`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpdateArgs {
    pub what: UpdateKind,
}

/// How to switch the machine off.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PowerKind {
    Restart,
    Shutdown,
}

/// Arguments of [`Action::Power`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PowerArgs {
    pub how: PowerKind,
}

#[cfg(test)]
mod tests;
