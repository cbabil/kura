//! The App Catalog (ADR-032): what Kura ships and what is installed, and
//! the one job at a time that installs, updates or removes an app.

use kura_desktop_core::catalog::{AppChange, Catalog, read_apps};
use kura_desktop_core::updates::Job;

use super::{Service, json};
use crate::policy::Action;
use crate::refusal::Refusal;

impl Service {
    /// The apps of the catalog with what is installed of each, and the last
    /// job with what it wrote, as the JSON of `Catalog` in the interface.
    ///
    /// # Errors
    /// [`Refusal::Admin`] for anyone else.
    pub(super) async fn read_catalog(&self, ticket: &str) -> Result<String, Refusal> {
        self.admit(ticket, Action::ReadCatalog)?;
        let _slot = self.slot()?;
        let job = match self.apps.job_state().await {
            Some(state) => Some(Job { state, output: self.apps.job_output().await }),
            None => None,
        };
        json(&Catalog { apps: read_apps(&self.root), job })
    }

    /// Installs, updates or removes one app of the catalog, as a job of
    /// its own. Only what the catalog holds, and only a port: nothing else
    /// about an app can be chosen from a browser.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for an app that is not in the catalog, one
    /// installed twice or not at all, or a port that will not do;
    /// [`Refusal::Busy`] while another job runs; [`Refusal::Unavailable`]
    /// when the job cannot start.
    pub(super) async fn change_app(&self, ticket: &str, change: &AppChange) -> Result<(), Refusal> {
        let account = self.admit(ticket, Action::ChangeApp)?;
        // Held from the look to the start, so two requests cannot both start.
        let _starting = self.starting.lock().await;
        if self.working().await {
            return Err(Refusal::Busy);
        }
        let args = change.command(&read_apps(&self.root)).map_err(|e| Refusal::Invalid(e.to_string()))?;
        let started = self.apps.start(args).await;
        tracing::info!(user = account.name, change = change.name(), app = change.id(), ok = started.is_ok(), "app");
        started.map_err(Refusal::Unavailable)
    }
}
