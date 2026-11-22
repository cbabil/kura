//! Local accounts from `/etc/passwd` and `/etc/group`: user ids for sessions
//! and preferences, names for the process table, and `sudo` membership.

use std::collections::HashMap;

use crate::root::SysRoot;

/// One `/etc/passwd` entry, reduced to what Kura Desktop needs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Account {
    pub name: String,
    pub uid: u32,
    pub gid: u32,
    /// The login shell; empty when the entry names none.
    pub shell: String,
}

/// The lowest uid of a person's account (Debian's `FIRST_UID`); root and
/// system accounts cannot sign in over the network or get a terminal.
pub const MIN_UID: u32 = 1000;
/// `nobody`, which is above [`MIN_UID`] but is not a person.
const NOBODY: u32 = 65534;

impl Account {
    /// True for a person's account: not root, a system account or `nobody`.
    pub fn is_person(&self) -> bool {
        self.uid >= MIN_UID && self.uid != NOBODY
    }
}

/// The accounts and groups read once from a [`SysRoot`].
#[derive(Debug, Clone, Default)]
pub struct Accounts {
    users: Vec<Account>,
    /// Group name to (gid, member names).
    groups: HashMap<String, (u32, Vec<String>)>,
}

impl Accounts {
    /// Reads `/etc/passwd` and `/etc/group`; a missing file reads as empty.
    pub fn load(root: &SysRoot) -> Self {
        let passwd = root.read("/etc/passwd").unwrap_or_default();
        let group = root.read("/etc/group").unwrap_or_default();
        Self::parse(&passwd, &group)
    }

    /// Parses the text of `/etc/passwd` and `/etc/group`; bad lines are skipped.
    pub fn parse(passwd: &str, group: &str) -> Self {
        let users = passwd.lines().filter_map(parse_user).collect();
        let groups = group.lines().filter_map(parse_group).collect();
        Self { users, groups }
    }

    /// Finds an account by name.
    pub fn by_name(&self, name: &str) -> Option<&Account> {
        self.users.iter().find(|a| a.name == name)
    }

    /// The people's accounts, in the order of `/etc/passwd`.
    pub fn people(&self) -> impl Iterator<Item = &Account> {
        self.users.iter().filter(|a| a.is_person())
    }

    /// The name for a uid, or the uid itself when there is no entry.
    pub fn name_of(&self, uid: u32) -> String {
        self.users.iter().find(|a| a.uid == uid).map_or_else(|| uid.to_string(), |a| a.name.clone())
    }

    /// True when `user` is in `group`, as a listed member or by primary gid.
    pub fn in_group(&self, user: &str, group: &str) -> bool {
        let Some((gid, members)) = self.groups.get(group) else {
            return false;
        };
        members.iter().any(|m| m == user) || self.by_name(user).is_some_and(|a| a.gid == *gid)
    }
}

fn parse_user(line: &str) -> Option<Account> {
    let mut f = line.split(':');
    let name = f.next().filter(|n| !n.is_empty())?.to_owned();
    let uid = f.nth(1)?.parse().ok()?;
    let gid = f.next()?.parse().ok()?;
    let shell = f.nth(2).unwrap_or("").to_owned();
    Some(Account { name, uid, gid, shell })
}

fn parse_group(line: &str) -> Option<(String, (u32, Vec<String>))> {
    let mut f = line.split(':');
    let name = f.next().filter(|n| !n.is_empty())?.to_owned();
    let gid = f.nth(1)?.parse().ok()?;
    let members = f.next().unwrap_or("").split(',').filter(|m| !m.is_empty()).map(str::to_owned).collect();
    Some((name, (gid, members)))
}

#[cfg(test)]
mod tests {
    use super::*;

    const PASSWD: &str = "root:x:0:0:root:/root:/bin/bash\n\
        kura:x:1000:1000:Kura:/home/kura:/bin/bash\n\
        anna:x:1001:27::/home/anna:/bin/bash\n\
        broken line\n:x:5:5::/:/bin/sh\n";
    const GROUP: &str = "root:x:0:\nsudo:x:27:kura\nusers:x:100:\nbad\n";

    #[test]
    fn parses_users_and_skips_bad_lines() {
        let a = Accounts::parse(PASSWD, GROUP);
        assert_eq!(
            a.by_name("kura").map(|u| (u.uid, u.shell.as_str(), u.is_person())),
            Some((1000, "/bin/bash", true))
        );
        assert!(!a.by_name("root").unwrap().is_person());
        let odd = Accounts::parse("nobody:x:65534:65534::/:/bin/sh\nshort:x:1001:1001\n", "");
        assert!(!odd.by_name("nobody").unwrap().is_person());
        assert_eq!(odd.by_name("short").map(|u| u.shell.as_str()), Some(""));
        assert_eq!(a.users.len(), 3);
        assert_eq!(a.name_of(0), "root");
        assert_eq!(a.people().map(|p| p.name.as_str()).collect::<Vec<_>>(), ["kura", "anna"]);
        assert_eq!(a.name_of(4242), "4242");
    }

    #[test]
    fn group_membership_by_list_or_primary_gid() {
        let a = Accounts::parse(PASSWD, GROUP);
        let cases = [("kura", "sudo", true), ("anna", "sudo", true), ("root", "sudo", false), ("kura", "nope", false)];
        for (user, group, want) in cases {
            assert_eq!(a.in_group(user, group), want, "{user} in {group}");
        }
    }

    #[test]
    fn load_reads_under_the_root_and_tolerates_missing_files() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("etc")).unwrap();
        std::fs::write(dir.path().join("etc/passwd"), PASSWD).unwrap();
        let a = Accounts::load(&SysRoot::new(dir.path()));
        assert!(a.by_name("anna").is_some());
        assert!(!a.in_group("kura", "sudo"));
    }
}
