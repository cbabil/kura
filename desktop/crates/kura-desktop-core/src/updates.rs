//! What the device knows about updates, as the desktop shows it (ADR-025:
//! installing is the owner's decision, and nothing restarts by itself). The
//! same facts the login screen reads through `scripts/common/updates.sh`.

use serde::Serialize;

use crate::root::SysRoot;

/// Kura's own package.
pub const PACKAGE: &str = "kura";
/// The file holding the installed version (`BRAND_VERSION="x.y.z"`).
pub const RELEASE_FILE: &str = "/usr/lib/kura/release";
/// Present once something installed needs a restart to take effect.
pub const RESTART_MARKER: &str = "/run/reboot-required";
/// The most lines of a job's output sent to the desktop.
pub const MAX_OUTPUT_LINES: usize = 200;

/// How far a job is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum JobState {
    Running,
    Done,
    Failed,
}

/// A job the helper asked systemd to run, as `Job` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Job {
    pub state: JobState,
    /// The last lines it wrote; empty for a user who is not an administrator.
    pub output: Vec<String>,
}

/// `UpdateStatus` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateStatus {
    /// The installed Kura version, or "" when the device cannot say.
    pub current: String,
    /// The version waiting in the repository, if a newer one does.
    pub available: Option<String>,
    pub restart_required: bool,
    /// The last check or installation, if one ran since the machine started.
    pub job: Option<Job>,
}

/// The installed version from [`RELEASE_FILE`]; "" when it is missing.
pub fn installed_version(root: &SysRoot) -> String {
    let text = root.read(RELEASE_FILE).unwrap_or_default();
    let value = text.lines().find_map(|l| l.strip_prefix("BRAND_VERSION="));
    value.unwrap_or("").trim().trim_matches('"').to_owned()
}

/// True when [`RESTART_MARKER`] exists.
pub fn restart_required(root: &SysRoot) -> bool {
    root.path(RESTART_MARKER).exists()
}

/// The repository's version from the output of `apt-cache policy <package>`,
/// when it differs from the installed one (`newer_version` in updates.sh).
/// `None` when up to date or when apt cannot say.
pub fn newer_version(policy: &str) -> Option<String> {
    let field = |name: &str| policy.lines().find_map(|l| l.trim().strip_prefix(name)).map(str::trim);
    let (have, want) = (field("Installed:")?, field("Candidate:")?);
    let known = |v: &str| !v.is_empty() && v != "(none)";
    (known(have) && known(want) && have != want).then(|| want.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_installed_version_and_the_restart_marker() {
        let dir = tempfile::tempdir().unwrap();
        let root = SysRoot::new(dir.path());
        assert_eq!((installed_version(&root).as_str(), restart_required(&root)), ("", false));
        std::fs::create_dir_all(dir.path().join("usr/lib/kura")).unwrap();
        std::fs::create_dir_all(dir.path().join("run")).unwrap();
        std::fs::write(dir.path().join("usr/lib/kura/release"), "BRAND_VERSION=\"0.6.1\"\n").unwrap();
        std::fs::write(dir.path().join("run/reboot-required"), "").unwrap();
        assert_eq!((installed_version(&root).as_str(), restart_required(&root)), ("0.6.1", true));
    }

    #[test]
    fn a_newer_version_is_the_candidate_that_differs() {
        let policy =
            |have: &str, want: &str| format!("kura:\n  Installed: {have}\n  Candidate: {want}\n  Version table:\n");
        let cases = [
            (policy("0.6.1", "0.6.2"), Some("0.6.2")),
            (policy("0.6.1", "0.6.1"), None),
            (policy("(none)", "0.6.2"), None),
            (policy("0.6.1", "(none)"), None),
            (String::new(), None),
            ("N: Unable to locate package kura".to_owned(), None),
        ];
        for (text, want) in cases {
            assert_eq!(newer_version(&text).as_deref(), want, "{text}");
        }
    }

    #[test]
    fn serializes_like_the_interface() {
        let status = UpdateStatus {
            current: "0.6.1".into(),
            available: Some("0.6.2".into()),
            restart_required: false,
            job: Some(Job { state: JobState::Running, output: vec!["Get:1".into()] }),
        };
        assert_eq!(
            serde_json::to_value(&status).unwrap(),
            serde_json::json!({"current":"0.6.1","available":"0.6.2","restartRequired":false,
                "job":{"state":"running","output":["Get:1"]}})
        );
    }
}
