//! Settings as the desktop shows and changes them (ADR-029): what is read
//! (`Settings`, as in types.ts), and each change with its checks. A change
//! becomes the arguments of the root command `kura-settings`, which checks
//! everything again; a password travels apart from the arguments.

mod change;
mod check;
mod read;

pub use change::{Change, Command, InvalidChange};
pub use read::{CONFIG, PENDING, STORAGE_STATUS, parse_devices, parse_time, read_config, screen};

use serde::Serialize;

/// Everything Settings shows, as `Settings` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Settings {
    pub hostname: String,
    pub network: Network,
    pub time: Time,
    pub users: Vec<Person>,
    /// How the disk layout went at first boot ("applied", "skipped: …"), or "".
    pub storage: String,
    /// The local screen (ADR-033): on or off, or `None` on a server whose
    /// image has none.
    pub screen: Option<bool>,
}

/// The network: the devices as they are now, and what Kura was told.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Network {
    pub devices: Vec<Device>,
    /// The names of the saved Wi-Fi networks (never their passwords).
    pub wifi: Vec<String>,
    pub ethernet: Ethernet,
    /// An address change waits to be confirmed, and goes back if it is not.
    pub pending: bool,
}

/// An Ethernet or Wi-Fi device.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Device {
    pub name: String,
    /// "ethernet" or "wifi".
    pub kind: String,
    pub connected: bool,
    /// The connection in use (a Wi-Fi network's name), or "".
    pub connection: String,
    pub mac: String,
    /// IPv4 addresses with their prefix, e.g. "192.168.1.50/24".
    pub addresses: Vec<String>,
    pub gateway: String,
    pub dns: Vec<String>,
}

/// The Ethernet address Kura was told to use.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Ethernet {
    /// "auto" (DHCP) or "manual".
    pub method: String,
    pub address: String,
    pub gateway: String,
    pub dns: Vec<String>,
}

impl Default for Ethernet {
    fn default() -> Self {
        Self { method: "auto".into(), address: String::new(), gateway: String::new(), dns: Vec::new() }
    }
}

/// The clock.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Time {
    pub zone: String,
    /// Network time is on.
    pub ntp: bool,
    /// The clock has been set from the network.
    pub synced: bool,
}

/// A person's account.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Person {
    pub name: String,
    pub uid: u32,
    pub admin: bool,
}
