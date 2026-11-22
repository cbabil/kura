//! The shape each value of a change must have. The root command
//! `kura-settings` checks the same things again.

use crate::auth::MAX_PASSWORD_BYTES;

/// The name of os-config's own Ethernet connection, which a Wi-Fi network
/// must not take (their connection files would be the same file).
const ETHERNET_CONNECTION: &str = "kura-ethernet";

/// A plain host name: lowercase letters, digits and inner hyphens, 63 at most.
pub fn valid_hostname(name: &str) -> bool {
    let edge = |c: Option<char>| c.is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit());
    (1..=63).contains(&name.len())
        && edge(name.chars().next())
        && edge(name.chars().last())
        && name.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// A Wi-Fi name os-config accepts (`SAFE_SSID_RE`), 32 bytes at most.
pub fn valid_ssid(ssid: &str) -> bool {
    let first = ssid.chars().next().is_some_and(|c| c.is_ascii_alphanumeric());
    let plain = ssid.chars().all(|c| c.is_ascii_alphanumeric() || " _.-".contains(c));
    first && plain && ssid.len() <= 32 && ssid != ETHERNET_CONNECTION
}

/// An IANA zone name's shape (it starts with a letter or digit, so it is
/// never read as an option); the root command checks that the zone exists.
pub fn valid_zone(zone: &str) -> bool {
    let part = |p: &str| !p.is_empty() && p.chars().all(|c| c.is_ascii_alphanumeric() || "_+-".contains(c));
    let parts: Vec<&str> = zone.split('/').collect();
    let first = zone.chars().next().is_some_and(|c| c.is_ascii_alphanumeric());
    first && (1..=3).contains(&parts.len()) && zone.len() <= 64 && parts.iter().all(|p| part(p))
}

/// A real IPv4 address in the usual four-number form (not 0.0.0.0).
pub fn valid_ipv4(text: &str) -> bool {
    text.parse::<std::net::Ipv4Addr>().is_ok_and(|a| !a.is_unspecified())
}

/// An IPv4 address with a prefix of 1 to 32, as `192.168.1.50/24`.
pub fn valid_cidr(text: &str) -> bool {
    text.split_once('/').is_some_and(|(address, prefix)| {
        valid_ipv4(address) && !prefix.starts_with('0') && prefix.parse::<u8>().is_ok_and(|p| (1..=32).contains(&p))
    })
}

/// A password chpasswd can take: 1 to 512 bytes, one line.
pub fn valid_password(password: &str) -> bool {
    (1..=MAX_PASSWORD_BYTES).contains(&password.len()) && !password.chars().any(|c| c == '\0' || c == '\n' || c == '\r')
}
