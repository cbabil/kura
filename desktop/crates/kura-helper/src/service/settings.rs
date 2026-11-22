//! Settings: what is shown, each change, and one's own password. A change
//! is checked here (`Change::command`), then by the root command it runs.

use kura_desktop_core::accounts::Accounts;
use kura_desktop_core::actions::{Action, OwnPasswordArgs};
use kura_desktop_core::auth::AuthOutcome;
use kura_desktop_core::settings::{
    Change, Network, PENDING, Person, STORAGE_STATUS, Settings, parse_devices, parse_time, read_config, screen,
};

use super::{Service, json};
use crate::authenticate::ADMIN_GROUP;
use crate::refusal::Refusal;

impl Service {
    /// Everything Settings shows, as the JSON of `Settings` in types.ts.
    ///
    /// # Errors
    /// [`Refusal::Admin`] for a user who is not an administrator.
    pub(super) async fn read_settings(&self, ticket: &str) -> Result<String, Refusal> {
        self.admit(ticket, Action::ReadSettings)?;
        let _slot = self.slot()?;
        let (hostname, wifi, ethernet) = read_config(&self.root);
        let accounts = Accounts::load(&self.root);
        let person = |a: &kura_desktop_core::accounts::Account| Person {
            name: a.name.clone(),
            uid: a.uid,
            admin: accounts.in_group(&a.name, ADMIN_GROUP),
        };
        json(&Settings {
            hostname,
            network: Network {
                devices: parse_devices(&self.system.devices().await),
                wifi,
                ethernet,
                pending: self.root.path(PENDING).exists(),
            },
            time: parse_time(&self.system.clock().await),
            users: accounts.people().map(person).collect(),
            storage: self.root.read(STORAGE_STATUS).unwrap_or_default().trim().to_owned(),
            screen: screen(&self.root),
        })
    }

    /// Runs a checked change, one at a time.
    async fn run(&self, change: &Change) -> Result<(), Refusal> {
        let command = change.command().map_err(|e| Refusal::Invalid(e.to_string()))?;
        let _one = self.changing.lock().await;
        self.system.change(command).await.map_err(Refusal::Unavailable)
    }

    /// Ends every sign-in of `user` but the ticket `keep`, with the shells
    /// and file agents started under them.
    async fn end_sign_ins(&self, user: &str, keep: Option<&str>) {
        self.gate.sign_out_user(user, keep);
        self.terminals.close_user(user, keep).await;
    }

    /// Makes one change. Two things nobody does to their own account from
    /// here: remove it (a slip would lock them out; another administrator
    /// can), and set its password (that needs the current one, see
    /// [`Service::change_own_password`]). A person whose password changed
    /// or who was removed is signed out everywhere.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] for a value that is not what it should be or a
    /// change the rules forbid; [`Refusal::Unavailable`] when the root
    /// command refused.
    pub(super) async fn change_setting(&self, ticket: &str, change: &Change) -> Result<(), Refusal> {
        let account = self.admit(ticket, Action::ChangeSetting)?;
        let own = change.user() == Some(account.name.as_str());
        if own && matches!(change, Change::UserRemove { .. } | Change::UserPassword { .. }) {
            return Err(Refusal::Invalid("your own account".into()));
        }
        let done = self.run(change).await;
        tracing::info!(
            user = account.name,
            change = change.name(),
            about = change.user(),
            ok = done.is_ok(),
            "setting"
        );
        if let (Ok(()), Change::UserRemove { name } | Change::UserPassword { name, .. }) = (&done, change) {
            self.end_sign_ins(name, None).await;
        }
        done
    }

    /// Changes the ticket's own user's password, once the current one is
    /// checked: an open browser alone is not enough. Their other sign-ins
    /// end; this one stays.
    ///
    /// # Errors
    /// [`Refusal::Invalid`] when the current password is wrong or the new
    /// one is not acceptable.
    pub(super) async fn change_own_password(&self, ticket: &str, args: OwnPasswordArgs) -> Result<(), Refusal> {
        let account = self.admit(ticket, Action::ChangeOwnPassword)?;
        let outcome = self.verify(&account.name, args.current.into()).await;
        if !matches!(outcome, AuthOutcome::Ok { .. } | AuthOutcome::Expired) {
            return Err(Refusal::Invalid("current password".into()));
        }
        let done = self.run(&Change::UserPassword { name: account.name.clone(), password: args.password }).await;
        tracing::info!(user = account.name, ok = done.is_ok(), "own password");
        if done.is_ok() {
            self.end_sign_ins(&account.name, Some(ticket)).await;
        }
        done
    }
}
