//! The journal for the Console app: `journalctl` run as root with arguments
//! that only a checked [`JournalQuery`] can produce. No shell is involved.

use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use kura_desktop_core::journal::{JournalPage, JournalQuery, parse_page};
use tokio::io::AsyncReadExt;

use crate::Fut;

/// journalctl on Debian.
pub const JOURNALCTL: &str = "/usr/bin/journalctl";
/// The fields the Console shows; the cursor and the time always come.
const FIELDS: &str = "--output-fields=MESSAGE,PRIORITY,_SYSTEMD_UNIT,UNIT,SYSLOG_IDENTIFIER,_COMM,_PID";
/// How long journalctl may take.
const TIMEOUT: Duration = Duration::from_secs(10);
/// The most output read.
const MAX_OUTPUT: u64 = 8 << 20;

/// The journal could not be read.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("journal: {0}")]
pub struct JournalError(pub String);

/// Reads journal entries.
pub trait Journal: Send + Sync {
    /// The entries matching `query`, oldest first.
    fn read<'a>(&'a self, query: &'a JournalQuery) -> Fut<'a, Result<JournalPage, JournalError>>;
}

/// The real journal, through the `journalctl` program.
pub struct Journalctl {
    program: PathBuf,
}

impl Default for Journalctl {
    fn default() -> Self {
        Self::new(JOURNALCTL)
    }
}

impl Journalctl {
    /// Runs `program` as journalctl.
    pub fn new(program: impl Into<PathBuf>) -> Self {
        Self { program: program.into() }
    }

    async fn run(&self, query: &JournalQuery) -> Result<JournalPage, JournalError> {
        let failed = |e: &dyn std::fmt::Display| JournalError(e.to_string());
        let mut child = tokio::process::Command::new(&self.program)
            .args(query.to_args())
            .arg(FIELDS)
            .env_clear()
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| failed(&e))?;
        let stdout = child.stdout.take().ok_or_else(|| failed(&"no output"))?;
        let read = async {
            let mut out = Vec::new();
            stdout.take(MAX_OUTPUT).read_to_end(&mut out).await.map_err(|e| failed(&e))?;
            // Past the limit journalctl is stopped (kill_on_drop), not waited for.
            if (out.len() as u64) < MAX_OUTPUT && !child.wait().await.map_err(|e| failed(&e))?.success() {
                return Err(failed(&"journalctl failed"));
            }
            Ok(parse_page(&out))
        };
        tokio::time::timeout(TIMEOUT, read).await.map_err(|_| failed(&"no answer in time"))?
    }
}

impl Journal for Journalctl {
    fn read<'a>(&'a self, query: &'a JournalQuery) -> Fut<'a, Result<JournalPage, JournalError>> {
        Box::pin(self.run(query))
    }
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::PermissionsExt;

    use super::*;

    /// A script standing in for journalctl; it also records its arguments.
    fn script(body: &str) -> (Journalctl, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("journalctl");
        let args = dir.path().join("args");
        // Written elsewhere, then copied by another program: Linux will not
        // run a file that any process has open for writing, and the other
        // tests' own programs, started meanwhile, would hold this one open.
        let text = dir.path().join("journalctl.txt");
        std::fs::write(&text, format!("#!/bin/sh\necho \"$@\" > {}\n{body}\n", args.display())).unwrap();
        assert!(std::process::Command::new("cp").arg(&text).arg(&path).status().unwrap().success());
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        (Journalctl::new(path), dir)
    }

    #[tokio::test]
    async fn runs_journalctl_with_the_querys_arguments() {
        let line = r#"{"__CURSOR":"s=1","__REALTIME_TIMESTAMP":"2000","MESSAGE":"hello"}"#;
        let (journal, dir) = script(&format!("echo '{line}'"));
        let query = JournalQuery::new(20, "ssh.service", 4, "").unwrap();
        let page = journal.read(&query).await.unwrap();
        assert_eq!((page.entries[0].message.as_str(), page.cursor.as_deref()), ("hello", Some("s=1")));
        let args = std::fs::read_to_string(dir.path().join("args")).unwrap();
        assert_eq!(
            args.trim(),
            format!("--output=json --all --no-pager --quiet --lines=20 --unit=ssh.service --priority=4 {FIELDS}")
        );
    }

    #[tokio::test]
    async fn failures_are_errors() {
        let query = JournalQuery::new(1, "", -1, "").unwrap();
        let (failing, _dir) = script("exit 1");
        assert!(failing.read(&query).await.unwrap_err().to_string().contains("failed"));
        let missing = Journalctl::new("/nonexistent-kura/journalctl");
        assert!(missing.read(&query).await.is_err());
        assert_eq!(Journalctl::default().program, PathBuf::from(JOURNALCTL));
    }
}
