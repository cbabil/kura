//! One change to a setting, as the interface sends it, and the checked
//! command line it becomes for `kura-settings`.

use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

use super::check::{valid_cidr, valid_hostname, valid_ipv4, valid_password, valid_ssid, valid_zone};
use crate::auth::valid_user_name;

/// A change Settings can make. Administrators only.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "what", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Change {
    Hostname {
        name: String,
    },
    Timezone {
        zone: String,
    },
    Ntp {
        on: bool,
    },
    /// The local screen, on a server whose image has one.
    Screen {
        on: bool,
    },
    /// Remote Desktop (ADR-035), on a server whose image has it.
    Rdp {
        on: bool,
    },
    WifiAdd {
        ssid: String,
        password: String,
        hidden: bool,
    },
    WifiRemove {
        ssid: String,
    },
    /// The Ethernet address from the network (DHCP).
    EthernetAuto,
    EthernetStatic {
        address: String,
        gateway: String,
        dns: Vec<String>,
    },
    /// The new address works: keep it.
    NetworkConfirm,
    UserAdd {
        name: String,
        password: String,
        admin: bool,
    },
    UserRemove {
        name: String,
    },
    UserAdmin {
        name: String,
        admin: bool,
    },
    UserPassword {
        name: String,
        password: String,
    },
}

/// Why a change was refused before anything ran.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("not a valid {0}")]
pub struct InvalidChange(pub &'static str);

/// A checked change: the arguments for `kura-settings`, and the password
/// that goes with them, apart.
pub struct Command {
    pub args: Vec<String>,
    pub secret: Option<Zeroizing<String>>,
}

impl Change {
    /// The name of the change, for the journal (never its values).
    pub fn name(&self) -> &'static str {
        match self {
            Self::Hostname { .. } => "hostname",
            Self::Timezone { .. } => "timezone",
            Self::Ntp { .. } => "ntp",
            Self::Screen { .. } => "screen",
            Self::Rdp { .. } => "rdp",
            Self::WifiAdd { .. } => "wifi-add",
            Self::WifiRemove { .. } => "wifi-remove",
            Self::EthernetAuto | Self::EthernetStatic { .. } => "ethernet",
            Self::NetworkConfirm => "network-confirm",
            Self::UserAdd { .. } => "user-add",
            Self::UserRemove { .. } => "user-remove",
            Self::UserAdmin { .. } => "user-admin",
            Self::UserPassword { .. } => "user-password",
        }
    }

    /// The user a change is about, for the rules about oneself.
    pub fn user(&self) -> Option<&str> {
        match self {
            Self::UserRemove { name } | Self::UserAdmin { name, .. } | Self::UserPassword { name, .. } => Some(name),
            _ => None,
        }
    }

    /// Checks the change and turns it into a command for `kura-settings`.
    ///
    /// # Errors
    /// [`InvalidChange`] naming the value that is not what it should be.
    pub fn command(&self) -> Result<Command, InvalidChange> {
        let ok = |valid: bool, what: &'static str| if valid { Ok(()) } else { Err(InvalidChange(what)) };
        let word = |b: bool| if b { "true" } else { "false" };
        let switch = |on: bool| if on { "on" } else { "off" };
        let (args, secret): (Vec<&str>, Option<&String>) = match self {
            Self::Hostname { name } => (ok(valid_hostname(name), "host name").map(|()| vec!["hostname", name])?, None),
            Self::Timezone { zone } => (ok(valid_zone(zone), "time zone").map(|()| vec!["timezone", zone])?, None),
            Self::Ntp { on } => (vec!["ntp", switch(*on)], None),
            Self::Screen { on } => (vec!["screen", switch(*on)], None),
            Self::Rdp { on } => (vec!["rdp", switch(*on)], None),
            Self::WifiAdd { ssid, password, hidden } => {
                ok(valid_ssid(ssid), "network name")?;
                ok((8..=63).contains(&password.len()) && valid_password(password), "Wi-Fi password")?;
                (vec!["wifi-add", ssid, word(*hidden)], Some(password))
            }
            Self::WifiRemove { ssid } => {
                (ok(valid_ssid(ssid), "network name").map(|()| vec!["wifi-remove", ssid])?, None)
            }
            Self::EthernetAuto => (vec!["ethernet", "auto"], None),
            Self::EthernetStatic { address, gateway, dns } => {
                ok(valid_cidr(address), "address")?;
                ok(valid_ipv4(gateway), "gateway")?;
                ok((1..=3).contains(&dns.len()) && dns.iter().all(|d| valid_ipv4(d)), "DNS server")?;
                return Ok(Command {
                    args: vec!["ethernet".into(), "static".into(), address.clone(), gateway.clone(), dns.join(",")],
                    secret: None,
                });
            }
            Self::NetworkConfirm => (vec!["network-confirm"], None),
            Self::UserAdd { name, password, admin } => {
                ok(valid_user_name(name), "user name")?;
                ok(valid_password(password), "password")?;
                (vec!["user-add", name, word(*admin)], Some(password))
            }
            Self::UserRemove { name } => {
                (ok(valid_user_name(name), "user name").map(|()| vec!["user-remove", name])?, None)
            }
            Self::UserAdmin { name, admin } => {
                ok(valid_user_name(name), "user name")?;
                (vec!["user-admin", name, if *admin { "on" } else { "off" }], None)
            }
            Self::UserPassword { name, password } => {
                ok(valid_user_name(name), "user name")?;
                ok(valid_password(password), "password")?;
                (vec!["user-password", name], Some(password))
            }
        };
        Ok(Command {
            args: args.into_iter().map(str::to_owned).collect(),
            secret: secret.map(|s| Zeroizing::new(s.clone())),
        })
    }
}

/// Passwords stay out of logs: only the change's name is shown.
impl std::fmt::Debug for Change {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Change({})", self.name())
    }
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
