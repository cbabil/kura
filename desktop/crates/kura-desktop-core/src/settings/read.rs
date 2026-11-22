//! Reading what Settings shows: Kura's `config.json`, and the output of
//! `nmcli` and `timedatectl`.

use serde_json::Value;

use super::{Device, Ethernet, Time};
use crate::root::SysRoot;

/// Kura's configuration, which `kura-config` applies.
pub const CONFIG: &str = "/etc/kura/config.json";
/// Present while an address change waits to be confirmed.
pub const PENDING: &str = "/var/lib/kura/network-previous.json";
/// How the disk layout went at first boot.
pub const STORAGE_STATUS: &str = "/var/lib/kura/storage-status";

/// The host name, the saved Wi-Fi networks' names and the Ethernet address
/// from [`CONFIG`]; defaults when the file is missing or not JSON.
pub fn read_config(root: &SysRoot) -> (String, Vec<String>, Ethernet) {
    let config: Value = root.read(CONFIG).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(Value::Null);
    let text = |v: &Value| v.as_str().unwrap_or("").to_owned();
    let list = |v: &Value| v.as_array().map(|a| a.iter().map(text).collect()).unwrap_or_default();
    let networks = config["networkConfig"]["wifi"]["networks"].as_array();
    let wifi = networks.map(|n| n.iter().map(|w| text(&w["ssid"])).filter(|s| !s.is_empty()).collect());
    let ipv4 = &config["networkConfig"]["ethernet"]["ipv4"];
    let ethernet = if ipv4["method"] == "manual" {
        Ethernet {
            method: "manual".into(),
            address: text(&ipv4["address"]),
            gateway: text(&ipv4["gateway"]),
            dns: list(&ipv4["dns"]),
        }
    } else {
        Ethernet::default()
    };
    (text(&config["hostname"]), wifi.unwrap_or_default(), ethernet)
}

/// Splits a terse nmcli line at its first plain colon; `\:` and `\\` in the
/// value are a colon and a backslash.
fn terse(line: &str) -> Option<(&str, String)> {
    let (key, value) = line.split_once(':')?;
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        out.push(if c == '\\' { chars.next().unwrap_or('\\') } else { c });
    }
    Some((key, out))
}

/// The Ethernet and Wi-Fi devices from `nmcli -t -f GENERAL.DEVICE,
/// GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR,IP4.ADDRESS,
/// IP4.GATEWAY,IP4.DNS device show`: one block per device, a blank line
/// between them.
pub fn parse_devices(nmcli: &str) -> Vec<Device> {
    let mut devices = Vec::new();
    for block in nmcli.split("\n\n") {
        let mut d = Device::default();
        for (key, value) in block.lines().filter_map(terse) {
            // IP4.ADDRESS[1], IP4.DNS[2]: the number does not matter
            match key.split('[').next().unwrap_or(key) {
                "GENERAL.DEVICE" => d.name = value,
                "GENERAL.TYPE" => d.kind = value,
                "GENERAL.STATE" => d.connected = value.starts_with("100"),
                "GENERAL.CONNECTION" => d.connection = if value == "--" { String::new() } else { value },
                "GENERAL.HWADDR" => d.mac = value,
                "IP4.ADDRESS" => d.addresses.push(value),
                "IP4.GATEWAY" => d.gateway = if value == "--" { String::new() } else { value },
                "IP4.DNS" => d.dns.push(value),
                _ => {}
            }
        }
        if matches!(d.kind.as_str(), "ethernet" | "wifi") && !d.name.is_empty() {
            devices.push(d);
        }
    }
    devices
}

/// The clock from `timedatectl show -p Timezone -p NTP -p NTPSynchronized`.
pub fn parse_time(timedatectl: &str) -> Time {
    let field = |name: &str| timedatectl.lines().find_map(|l| l.strip_prefix(name)?.strip_prefix('=')).unwrap_or("");
    Time { zone: field("Timezone").to_owned(), ntp: field("NTP") == "yes", synced: field("NTPSynchronized") == "yes" }
}

/// The local screen's unit, and the link that turns it on.
const SCREEN_UNIT: &str = "/usr/lib/systemd/system/kura-kiosk.service";
const SCREEN_ON: &str = "/etc/systemd/system/multi-user.target.wants/kura-kiosk.service";

/// The browser's compositor: every PC image has the unit, only one built
/// for the local screen has this.
const SCREEN_PROGRAM: &str = "/usr/bin/cage";

/// Whether the local screen is on; `None` where the image has none.
pub fn screen(root: &crate::root::SysRoot) -> Option<bool> {
    let has = root.path(SCREEN_UNIT).exists() && root.path(SCREEN_PROGRAM).exists();
    // A link to a unit that is elsewhere on this machine still means "on".
    has.then(|| root.path(SCREEN_ON).symlink_metadata().is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    const NMCLI: &str = "GENERAL.DEVICE:enp1s0\nGENERAL.TYPE:ethernet\nGENERAL.HWADDR:AA\\:BB\\:CC\\:00\\:11\\:22\n\
        GENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:Wired connection 1\nIP4.ADDRESS[1]:192.168.1.50/24\n\
        IP4.GATEWAY:192.168.1.1\nIP4.DNS[1]:192.168.1.1\nIP4.DNS[2]:9.9.9.9\n\n\
        GENERAL.DEVICE:wlp2s0\nGENERAL.TYPE:wifi\nGENERAL.HWADDR:AA\\:BB\\:CC\\:00\\:11\\:33\nGENERAL.STATE:30 (disconnected)\n\
        GENERAL.CONNECTION:--\nIP4.GATEWAY:--\n\n\
        GENERAL.DEVICE:lo\nGENERAL.TYPE:loopback\nGENERAL.STATE:100 (connected (externally))\n\n\
        GENERAL.DEVICE:docker0\nGENERAL.TYPE:bridge\n";

    #[test]
    fn devices_from_nmcli() {
        let devices = parse_devices(NMCLI);
        assert_eq!(devices.iter().map(|d| d.name.as_str()).collect::<Vec<_>>(), ["enp1s0", "wlp2s0"]);
        let e = &devices[0];
        assert_eq!((e.kind.as_str(), e.connected, e.mac.as_str()), ("ethernet", true, "AA:BB:CC:00:11:22"));
        assert_eq!(
            (e.addresses.as_slice(), e.gateway.as_str(), e.dns.len()),
            (&["192.168.1.50/24".to_owned()][..], "192.168.1.1", 2)
        );
        let w = &devices[1];
        assert_eq!((w.connected, w.connection.as_str(), w.gateway.as_str(), w.addresses.len()), (false, "", "", 0));
        assert!(parse_devices("").is_empty() && parse_devices("garbage\n\nmore").is_empty());
    }

    #[test]
    fn the_clock_from_timedatectl() {
        let t = parse_time("Timezone=Europe/Paris\nNTP=yes\nNTPSynchronized=no\n");
        assert_eq!((t.zone.as_str(), t.ntp, t.synced), ("Europe/Paris", true, false));
        assert_eq!(parse_time(""), Time::default());
    }

    #[test]
    fn config_gives_names_and_never_passwords() {
        let dir = tempfile::tempdir().unwrap();
        let root = SysRoot::new(dir.path());
        assert_eq!(read_config(&root), (String::new(), vec![], Ethernet::default()));
        std::fs::create_dir_all(dir.path().join("etc/kura")).unwrap();
        let config = r#"{"hostname":"attic","networkConfig":{"wifi":{"networks":[{"ssid":"Home","psk":"secret pass"},{"psk":"x"}]},
            "ethernet":{"ipv4":{"method":"manual","address":"10.0.0.2/24","gateway":"10.0.0.1","dns":["10.0.0.1"]}}}}"#;
        std::fs::write(dir.path().join("etc/kura/config.json"), config).unwrap();
        let (host, wifi, ethernet) = read_config(&root);
        assert_eq!((host.as_str(), wifi, ethernet.method.as_str()), ("attic", vec!["Home".to_owned()], "manual"));
        assert_eq!(
            (ethernet.address.as_str(), ethernet.gateway.as_str(), ethernet.dns),
            ("10.0.0.2/24", "10.0.0.1", vec!["10.0.0.1".to_owned()])
        );
        std::fs::write(dir.path().join("etc/kura/config.json"), "{not json").unwrap();
        assert_eq!(read_config(&root).0, "");
    }
}
