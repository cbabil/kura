//! The development backends behind the real helper's service: a password
//! check, Docker, the journal and the machine (updates, power), all made
//! up (see `sample.rs`).

use std::sync::Mutex;

use kura_desktop_core::actions::{PowerKind, UpdateKind};
use kura_desktop_core::containers::{Container, ContainerAction, LogLine};
use kura_desktop_core::journal::{JournalPage, JournalQuery};
use kura_desktop_core::lock;
use kura_desktop_core::updates::JobState;
use kura_helper::docker::{Docker, DockerError};
use kura_helper::journal::{Journal, JournalError};
use kura_helper::machine::Machine;
use kura_helper::{Fut, Pam, PamVerdict};

use super::{DEV_PASSWORD, sample};

/// Accepts [`DEV_PASSWORD`] for every account; "expired" must change it.
pub struct DevPam;

impl Pam for DevPam {
    fn check(&self, user: &str, password: &str) -> PamVerdict {
        match (user, password == DEV_PASSWORD) {
            (_, false) => PamVerdict::Wrong,
            ("expired", true) => PamVerdict::Expired,
            _ => PamVerdict::Ok,
        }
    }
}

/// Sample containers whose state changes when they are acted on.
pub struct SampleDocker {
    containers: Mutex<Vec<Container>>,
}

impl Default for SampleDocker {
    fn default() -> Self {
        Self { containers: Mutex::new(sample::containers()) }
    }
}

impl Docker for SampleDocker {
    fn list(&self) -> Fut<'_, Result<Vec<Container>, DockerError>> {
        let list = lock(&self.containers).clone();
        Box::pin(async move { Ok(list) })
    }

    fn act<'a>(&'a self, id: &'a str, action: ContainerAction) -> Fut<'a, Result<(), DockerError>> {
        let done =
            lock(&self.containers).iter_mut().find(|c| c.id == id).ok_or(DockerError::NotFound).map(|container| {
                let (state, status) = match action {
                    ContainerAction::Stop => ("exited", "Exited (0) 1 second ago"),
                    ContainerAction::Start | ContainerAction::Restart => ("running", "Up 1 second"),
                };
                (container.state, container.status) = (state.into(), status.into());
            });
        Box::pin(async move { done })
    }

    fn logs<'a>(&'a self, id: &'a str, lines: u32) -> Fut<'a, Result<Vec<LogLine>, DockerError>> {
        let name = lock(&self.containers).iter().find(|c| c.id == id).map(|c| c.name.clone());
        Box::pin(async move { name.map(|name| sample::logs(&name, lines)).ok_or(DockerError::NotFound) })
    }
}

/// A short sample journal.
pub struct SampleJournal;

impl Journal for SampleJournal {
    fn read<'a>(&'a self, query: &'a JournalQuery) -> Fut<'a, Result<JournalPage, JournalError>> {
        Box::pin(async move { Ok(sample::journal(query)) })
    }
}

/// A machine that is never switched off: Kura 0.6.1 with 0.6.2 waiting,
/// and an update "job" that is done as soon as it starts.
#[derive(Default)]
pub struct DevMachine {
    last: Mutex<Option<UpdateKind>>,
}

impl Machine for DevMachine {
    fn power(&self, how: PowerKind) -> Fut<'_, Result<(), String>> {
        tracing::warn!(?how, "development build: the machine stays on");
        Box::pin(async { Ok(()) })
    }

    fn apt_policy(&self) -> Fut<'_, String> {
        let have = if *lock(&self.last) == Some(UpdateKind::Install) { "0.6.2" } else { "0.6.1" };
        Box::pin(async move { format!("kura:\n  Installed: {have}\n  Candidate: 0.6.2\n") })
    }

    fn start_update(&self, what: UpdateKind) -> Fut<'_, Result<(), String>> {
        *lock(&self.last) = Some(what);
        Box::pin(async { Ok(()) })
    }

    fn job_state(&self) -> Fut<'_, Option<JobState>> {
        let ran = lock(&self.last).is_some();
        Box::pin(async move { ran.then_some(JobState::Done) })
    }

    fn job_output(&self) -> Fut<'_, Vec<String>> {
        let lines: &[&str] = match *lock(&self.last) {
            Some(UpdateKind::Check) => {
                &["Hit:1 https://deb.debian.org/debian trixie InRelease", "Reading package lists..."]
            }
            Some(UpdateKind::Install) => &["Unpacking kura (0.6.2) over (0.6.1) ...", "Setting up kura (0.6.2) ..."],
            None => &[],
        };
        Box::pin(async move { lines.iter().map(|l| (*l).to_owned()).collect() })
    }

    fn browser(&self, on: bool) -> Fut<'_, Result<(), String>> {
        tracing::warn!(on, "development build: there is no browser to start");
        Box::pin(async { Ok(()) })
    }
}
