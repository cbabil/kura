//! Who may do what: the tickets that prove a sign-in, and the check of each
//! action's rule (the fixed list is `kura_desktop_core::actions::Action`,
//! ADR-027). A ticket is made when a password check
//! succeeds, so desktopd cannot act for a user who never signed in.

use std::time::{Duration, Instant};

use kura_desktop_core::accounts::{Account, Accounts};
pub use kura_desktop_core::actions::Action;
use kura_desktop_core::root::SysRoot;
use kura_desktop_core::session::IdleStore;

use crate::authenticate::ADMIN_GROUP;
use crate::refusal::Refusal;

/// Tickets one user may hold at once (one per signed-in browser); the
/// oldest goes first, so signing in again and again costs nobody else theirs.
pub const MAX_TICKETS_PER_USER: usize = 8;
/// A ticket ends this long after its sign-in, however much it is used.
pub const MAX_TICKET_AGE: Duration = Duration::from_secs(7 * 24 * 3600);

/// Tickets, and the check every action passes first.
pub struct Gate {
    tickets: IdleStore<String>,
    root: SysRoot,
}

impl Gate {
    /// A gate reading `/etc/passwd` and `/etc/group` under `root`.
    pub fn new(root: SysRoot) -> Self {
        Self { tickets: IdleStore::with_max_age(MAX_TICKET_AGE), root }
    }

    /// A new ticket for `user`, whose password was just checked.
    pub fn sign_in(&self, user: &str, now: Instant) -> String {
        self.tickets.create_capped(user.to_owned(), now, MAX_TICKETS_PER_USER, |owner| owner == user)
    }

    /// Ends a ticket; returns its user when it was live.
    pub fn sign_out(&self, ticket: &str) -> Option<String> {
        self.tickets.remove(ticket)
    }

    /// Ends every ticket of `user` but `keep` (after their password changed,
    /// or they were removed): a stolen session does not outlive the change.
    pub fn sign_out_user(&self, user: &str, keep: Option<&str>) {
        // The kept ticket is taken out, the rest ended, and it is put back.
        let kept = keep.and_then(|ticket| self.tickets.remove(ticket).filter(|owner| owner == user).map(|_| ticket));
        self.tickets.remove_where(|owner| owner == user);
        if let Some(ticket) = kept {
            self.tickets.restore(ticket, user.to_owned(), Instant::now());
        }
    }

    /// True when `user` is an administrator now.
    pub fn is_admin(&self, user: &str) -> bool {
        Accounts::load(&self.root).in_group(user, ADMIN_GROUP)
    }

    /// Marks a ticket used, as desktopd does for a session that is watched
    /// but asks nothing of the helper.
    ///
    /// # Errors
    /// [`Refusal::SignedOut`] when the ticket has ended.
    pub fn keep_alive(&self, ticket: &str, now: Instant) -> Result<(), Refusal> {
        if self.tickets.keep_alive(ticket, now) { Ok(()) } else { Err(Refusal::SignedOut) }
    }

    /// The account behind `ticket` if it may do `action` now. The account
    /// and its `sudo` membership are read afresh, so removing a user or
    /// their rights takes effect at once.
    ///
    /// # Errors
    /// [`Refusal::SignedOut`] without a live ticket of a person's account;
    /// [`Refusal::Admin`] when the action needs an administrator.
    pub fn check(&self, ticket: &str, action: Action, now: Instant) -> Result<Account, Refusal> {
        let user = self.tickets.touch(ticket, now).ok_or(Refusal::SignedOut)?;
        let accounts = Accounts::load(&self.root);
        let Some(account) = accounts.by_name(&user).filter(|a| a.is_person()) else {
            self.tickets.remove(ticket);
            return Err(Refusal::SignedOut);
        };
        if action.needs_admin() && !accounts.in_group(&user, ADMIN_GROUP) {
            return Err(Refusal::Admin);
        }
        Ok(account.clone())
    }
}

#[cfg(test)]
mod tests {
    use kura_desktop_core::session::IDLE_TIMEOUT;

    use super::*;
    use crate::authenticate::tests::root;

    const ADMIN_ONLY: [Action; 5] =
        [Action::ControlContainer, Action::ContainerLogs, Action::ReadJournal, Action::StartUpdate, Action::Power];

    fn gate() -> (Gate, tempfile::TempDir) {
        let (root, dir) = root();
        (Gate::new(root), dir)
    }

    #[test]
    fn a_ticket_opens_what_its_user_may_do() {
        let (gate, _dir) = gate();
        let now = Instant::now();
        let (anna, bob) = (gate.sign_in("anna", now), gate.sign_in("bob", now));
        for action in [Action::Terminal, Action::ListContainers, Action::UpdateStatus] {
            assert_eq!(gate.check(&bob, action, now).unwrap().name, "bob");
        }
        for action in ADMIN_ONLY {
            assert_eq!(gate.check(&bob, action, now), Err(Refusal::Admin), "{action:?}");
            assert_eq!(gate.check(&anna, action, now).unwrap().uid, 1000);
        }
        assert!(gate.is_admin("anna") && !gate.is_admin("bob"));
    }

    #[test]
    fn no_ticket_no_action() {
        let (gate, _dir) = gate();
        let now = Instant::now();
        let bob = gate.sign_in("bob", now);
        assert_eq!(gate.check("forged", Action::Terminal, now), Err(Refusal::SignedOut));
        assert_eq!(gate.check("", Action::ListContainers, now), Err(Refusal::SignedOut));
        assert!(gate.check(&bob, Action::Terminal, now + IDLE_TIMEOUT).is_err(), "idle tickets end");
        let bob = gate.sign_in("bob", now);
        assert_eq!(gate.sign_out(&bob).as_deref(), Some("bob"));
        assert_eq!(gate.check(&bob, Action::Terminal, now), Err(Refusal::SignedOut));
        // a ticket never makes root or a system account a person
        for user in ["root", "daemon", "nobody", "ghost"] {
            let t = gate.sign_in(user, now);
            assert_eq!(gate.check(&t, Action::Terminal, now), Err(Refusal::SignedOut), "{user}");
        }
    }

    #[test]
    fn tickets_are_capped_per_user_and_age() {
        let (gate, _dir) = gate();
        let now = Instant::now();
        let anna = gate.sign_in("anna", now);
        let first = gate.sign_in("bob", now);
        for i in 0..MAX_TICKETS_PER_USER as u64 {
            gate.sign_in("bob", now + Duration::from_secs(i + 1));
        }
        assert_eq!(gate.keep_alive(&first, now), Err(Refusal::SignedOut), "bob's oldest went");
        assert_eq!(gate.keep_alive(&anna, now), Ok(()), "anna's did not");
        let mut later = now;
        while later < now + MAX_TICKET_AGE - IDLE_TIMEOUT {
            later += IDLE_TIMEOUT / 2;
            assert_eq!(gate.keep_alive(&anna, later), Ok(()));
        }
        assert!(gate.check(&anna, Action::Terminal, now + MAX_TICKET_AGE).is_err(), "used all week, and still ended");
    }

    #[test]
    fn rights_are_read_afresh() {
        let (gate, dir) = gate();
        let now = Instant::now();
        let anna = gate.sign_in("anna", now);
        assert!(gate.check(&anna, Action::ReadJournal, now).is_ok());
        std::fs::write(dir.path().join("etc/group"), "sudo:x:27:\n").unwrap();
        assert_eq!(gate.check(&anna, Action::ReadJournal, now), Err(Refusal::Admin));
        std::fs::write(dir.path().join("etc/passwd"), "bob:x:1001:1001::/home/bob:/bin/sh\n").unwrap();
        assert_eq!(gate.check(&anna, Action::Terminal, now), Err(Refusal::SignedOut));
    }
}
