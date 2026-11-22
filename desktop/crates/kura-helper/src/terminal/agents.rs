//! The file agents (`kura-agent`, ADR-031): one for each ticket, for
//! people who have a login shell, and gone with the person's sign-ins.

use std::os::fd::OwnedFd;

use kura_desktop_core::accounts::Account;

use super::{Kind, Terminals};
use crate::refusal::Refusal;

impl Terminals {
    /// Starts `account`'s file agent, owned by `ticket`: its id and the
    /// socket to it. A ticket has one agent; an earlier one is stopped.
    /// Like a terminal, it is for accounts with a login shell: Files then
    /// reaches nothing its user could not reach in a terminal.
    ///
    /// # Errors
    /// As [`Terminals::open`], without the size.
    pub async fn open_agent(&self, ticket: &str, account: &Account) -> Result<(String, OwnedFd), Refusal> {
        if !self.login_shell(&account.shell) {
            return Err(Refusal::NoShell);
        }
        self.close_where(|o| o.ticket == ticket && o.kind == Kind::Agent).await;
        self.forget_ended(&account.name, Kind::Agent).await;
        self.start(ticket, account, Kind::Agent, self.launcher.open_agent(account)).await
    }

    /// Closes every terminal and agent of `user` but those of the ticket
    /// `keep`: after their password changed or they were removed, nothing
    /// started under an ended sign-in keeps running.
    pub async fn close_user(&self, user: &str, keep: Option<&str>) {
        self.close_where(|o| o.user == user && Some(o.ticket.as_str()) != keep).await;
    }
}
