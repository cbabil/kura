//! The actions asked by name: [`Service::ask`] reads the name and the
//! arguments (`kura_desktop_core::actions`) and calls the one method that
//! does it. Each method checks the ticket and the rule itself.

use kura_desktop_core::actions::{
    Action, ContainerArgs, JournalArgs, LogsArgs, OwnPasswordArgs, PowerArgs, PowerKind, UpdateArgs, UpdateKind,
};
use kura_desktop_core::catalog::AppChange;
use kura_desktop_core::containers::{ContainerAction, MAX_LOG_LINES, valid_container_id};
use kura_desktop_core::journal::JournalQuery;
use kura_desktop_core::settings::Change;
use kura_desktop_core::updates::{Job, JobState, UpdateStatus, installed_version, newer_version, restart_required};

use super::{Service, json};
use crate::refusal::Refusal;

/// Reads an action's arguments; anything else than its own shape is refused.
pub(super) fn parse<'a, T: serde::Deserialize<'a>>(args: &'a str) -> Result<T, Refusal> {
    serde_json::from_str(args).map_err(|_| Refusal::Invalid("arguments".into()))
}

impl Service {
    /// Does the action called `action` with the JSON `args`; the answer is
    /// JSON, or empty for an action that only does something.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for a name off the list or arguments that are
    /// not the action's; otherwise the action's own refusals.
    pub async fn ask(&self, ticket: &str, action: &str, args: &str) -> Result<String, Refusal> {
        let Some(action) = Action::parse(action) else {
            // Never from the interface: worth a line, without the name itself.
            tracing::warn!("asked for an action that is not on the list");
            return Err(Refusal::Invalid("action".into()));
        };
        let done = |()| String::new();
        match action {
            // A terminal's answer is a file descriptor: its own D-Bus method.
            Action::Terminal | Action::Files => Err(Refusal::Invalid("action".into())),
            Action::ListContainers | Action::UpdateStatus | Action::ReadSettings | Action::ReadCatalog
                if !matches!(args, "" | "null") =>
            {
                Err(Refusal::Invalid("arguments".into()))
            }
            Action::ListContainers => self.list_containers(ticket).await,
            Action::ControlContainer => {
                let a: ContainerArgs = parse(args)?;
                self.container_action(ticket, &a.id, a.action).await.map(done)
            }
            Action::ContainerLogs => {
                let a: LogsArgs = parse(args)?;
                self.container_logs(ticket, &a.id, a.lines).await
            }
            Action::ReadJournal => {
                let a: JournalArgs = parse(args)?;
                self.read_journal(ticket, a.lines, &a.unit, a.priority, &a.after).await
            }
            Action::UpdateStatus => self.update_status(ticket).await,
            Action::StartUpdate => self.start_update(ticket, parse::<UpdateArgs>(args)?.what).await.map(done),
            Action::Power => self.power(ticket, parse::<PowerArgs>(args)?.how).await.map(done),
            Action::ReadSettings => self.read_settings(ticket).await,
            Action::ChangeSetting => self.change_setting(ticket, &parse::<Change>(args)?).await.map(done),
            Action::ReadCatalog => self.read_catalog(ticket).await,
            Action::ChangeApp => self.change_app(ticket, &parse::<AppChange>(args)?).await.map(done),
            Action::ChangeOwnPassword => {
                self.change_own_password(ticket, parse::<OwnPasswordArgs>(args)?).await.map(done)
            }
        }
    }

    /// Every container, as the JSON of `Container[]` in types.ts.
    ///
    /// # Errors
    /// [`Refusal::Unavailable`] when Docker does not answer.
    pub(super) async fn list_containers(&self, ticket: &str) -> Result<String, Refusal> {
        self.admit(ticket, Action::ListContainers)?;
        let _slot = self.slot()?;
        json(&self.docker.list().await?)
    }

    /// Starts, stops or restarts a container.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for an id outside the fixed form.
    pub(super) async fn container_action(
        &self,
        ticket: &str,
        id: &str,
        action: ContainerAction,
    ) -> Result<(), Refusal> {
        let account = self.admit(ticket, Action::ControlContainer)?;
        let id = Some(id).filter(|id| valid_container_id(id)).ok_or_else(|| Refusal::Invalid("container id".into()))?;
        let _slot = self.slot()?;
        let done = self.docker.act(id, action).await;
        tracing::info!(user = account.name, action = action.as_str(), id, ok = done.is_ok(), "container");
        Ok(done?)
    }

    /// The last `lines` lines of a container, as the JSON of `LogLine[]`.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for a bad id or more than [`MAX_LOG_LINES`].
    pub(super) async fn container_logs(&self, ticket: &str, id: &str, lines: u32) -> Result<String, Refusal> {
        self.admit(ticket, Action::ContainerLogs)?;
        if !valid_container_id(id) || !(1..=MAX_LOG_LINES).contains(&lines) {
            return Err(Refusal::Invalid("container id or lines".into()));
        }
        let _slot = self.slot()?;
        json(&self.docker.logs(id, lines).await?)
    }

    /// Journal entries, as the JSON of `JournalPage` in types.ts.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for a query [`JournalQuery::new`] refuses.
    pub(super) async fn read_journal(
        &self,
        ticket: &str,
        lines: u32,
        unit: &str,
        priority: i32,
        after: &str,
    ) -> Result<String, Refusal> {
        self.admit(ticket, Action::ReadJournal)?;
        let query = JournalQuery::new(lines, unit, priority, after).map_err(|e| Refusal::Invalid(e.to_string()))?;
        let _slot = self.slot()?;
        let page = self.journal.read(&query).await.map_err(|e| Refusal::Unavailable(e.to_string()))?;
        json(&page)
    }

    /// The installed version, the waiting one, whether a restart is due and
    /// the last update job, as the JSON of `UpdateStatus` in types.ts. Only
    /// an administrator gets the job's output.
    ///
    /// # Errors
    /// [`Refusal::SignedOut`] without a live ticket.
    pub(super) async fn update_status(&self, ticket: &str) -> Result<String, Refusal> {
        let account = self.admit(ticket, Action::UpdateStatus)?;
        let _slot = self.slot()?;
        let job = match self.machine.job_state().await {
            Some(state) if self.gate.is_admin(&account.name) => {
                Some(Job { state, output: self.machine.job_output().await })
            }
            state => state.map(|state| Job { state, output: Vec::new() }),
        };
        json(&UpdateStatus {
            current: installed_version(&self.root),
            available: newer_version(&self.machine.apt_policy().await),
            restart_required: restart_required(&self.root),
            job,
        })
    }

    /// True while an update or a catalog job runs. One at a time, and the
    /// machine is not switched off under either: an upgrade can restart
    /// Docker under an installation, and a restart can cut either short.
    pub(super) async fn working(&self) -> bool {
        self.machine.job_state().await == Some(JobState::Running)
            || self.apps.job_state().await == Some(JobState::Running)
    }

    /// Refreshes the package lists or installs what waits, as a job of its
    /// own, one at a time. Never restarts the machine.
    ///
    /// # Errors
    /// [`Refusal::Busy`] while an update or a catalog job runs;
    /// [`Refusal::Unavailable`] when the job cannot start.
    pub(super) async fn start_update(&self, ticket: &str, what: UpdateKind) -> Result<(), Refusal> {
        let account = self.admit(ticket, Action::StartUpdate)?;
        // Held from the look to the start, so two requests cannot both start.
        let _starting = self.starting.lock().await;
        if self.working().await {
            return Err(Refusal::Busy);
        }
        let started = self.machine.start_update(what).await;
        tracing::info!(user = account.name, ?what, ok = started.is_ok(), "update");
        started.map_err(Refusal::Unavailable)
    }

    /// Restarts or shuts down the machine. Not while an update installs:
    /// cutting dpkg off half-way can leave a machine that does not start.
    ///
    /// # Errors
    /// [`Refusal::Busy`] while an update runs; [`Refusal::Unavailable`]
    /// when logind refuses.
    pub(super) async fn power(&self, ticket: &str, how: PowerKind) -> Result<(), Refusal> {
        let account = self.admit(ticket, Action::Power)?;
        if self.working().await {
            return Err(Refusal::Busy);
        }
        tracing::warn!(user = account.name, ?how, "power");
        self.machine.power(how).await.map_err(Refusal::Unavailable)
    }
}
