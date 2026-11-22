//! Sample containers, logs and journal entries for the fake helper, close
//! to the interface's mock API so both look alike.

use kura_desktop_core::containers::{Container, LogLine};
use kura_desktop_core::journal::{JournalEntry, JournalPage};

use kura_desktop_core::journal::JournalQuery;

/// A fixed "now" keeps the samples the same on every run: 2026-11-21 10:00 UTC.
const NOW_MS: i64 = 1_795_255_200_000;

/// A sample container: name, image, compose project and service, running,
/// published port.
type Sample = (&'static str, &'static str, Option<(&'static str, &'static str)>, bool, Option<u16>);

const CONTAINERS: [Sample; 7] = [
    ("immich-server", "ghcr.io/immich-app/immich-server:v2.3", Some(("immich", "server")), true, Some(2283)),
    ("immich-machine-learning", "ghcr.io/immich-app/immich-ml:v2.3", Some(("immich", "machine-learning")), true, None),
    ("immich-postgres", "tensorchord/pgvecto-rs:pg16", Some(("immich", "postgres")), true, None),
    ("immich-redis", "redis:7-alpine", Some(("immich", "redis")), true, None),
    ("jellyfin", "jellyfin/jellyfin:10.11", None, true, Some(8096)),
    ("homeassistant", "ghcr.io/home-assistant/home-assistant:2026.11", None, true, Some(8123)),
    ("pihole", "pihole/pihole:2026.10", None, false, Some(8080)),
];

/// The sample containers; ids are the index repeated as hex.
pub fn containers() -> Vec<Container> {
    let one = |(i, (name, image, compose, running, port)): (usize, Sample)| Container {
        id: format!("{:x}", i + 10).repeat(12),
        name: name.into(),
        image: image.into(),
        state: if running { "running" } else { "exited" }.into(),
        status: if running { "Up 3 days" } else { "Exited (0) 2 hours ago" }.into(),
        created: NOW_MS - 30 * 86_400_000,
        project: compose.map(|c| c.0.into()),
        service: compose.map(|c| c.1.into()),
        ports: port.into_iter().collect(),
    };
    CONTAINERS.into_iter().enumerate().map(one).collect()
}

/// The last `lines` of a container that logs once a minute.
pub fn logs(name: &str, lines: u32) -> Vec<LogLine> {
    let count = i64::from(lines.min(40));
    (0..count)
        .map(|i| LogLine {
            t: Some(NOW_MS - (count - 1 - i) * 60_000),
            stream: if i % 9 == 8 { "stderr" } else { "stdout" },
            text: if i % 9 == 8 {
                format!("{name}: request took 2.1 s")
            } else {
                format!("{name}: handled request {}", i + 1)
            },
        })
        .collect()
}

/// A sample journal entry: unit, program, priority, message.
type Entry = (&'static str, &'static str, u8, &'static str);

const JOURNAL: [Entry; 8] = [
    ("kura-desktopd.service", "kura-desktopd", 6, "listening on https://[::]:443"),
    ("docker.service", "dockerd", 6, "Container immich-server started"),
    ("ssh.service", "sshd", 6, "Accepted publickey for kura from 192.168.1.20"),
    ("docker.service", "dockerd", 4, "immich-machine-learning ran out of memory and was restarted"),
    ("unattended-upgrades.service", "unattended-upgrade", 6, "No packages found that can be upgraded unattended"),
    ("ssh.service", "sshd", 3, "Failed password for invalid user admin from 192.168.1.77"),
    ("kura-helper.service", "kura-helper", 6, "authenticate user=kura ok=true"),
    ("systemd-timesyncd.service", "systemd-timesyncd", 6, "Synchronized to time server 162.159.200.1:123"),
];

/// The sample journal, filtered as journalctl would.
pub fn journal(ask: &JournalQuery) -> JournalPage {
    let after: usize = ask.after().and_then(|c| c.strip_prefix("s=dev;i=")).and_then(|i| i.parse().ok()).unwrap_or(0);
    let all = JOURNAL.iter().enumerate().map(|(i, e)| (i + 1, e));
    let keep = |(i, (unit, _, priority, _)): &(usize, &Entry)| {
        *i > after && ask.unit().is_none_or(|u| u == *unit) && ask.priority().is_none_or(|p| *priority <= p)
    };
    let mut matching: Vec<_> = all.filter(keep).collect();
    let skip = matching.len().saturating_sub(ask.lines() as usize);
    let matching = matching.split_off(skip);
    JournalPage {
        cursor: matching.last().map(|(i, _)| format!("s=dev;i={i}")),
        entries: matching
            .into_iter()
            .map(|(i, (unit, ident, priority, message))| JournalEntry {
                t: NOW_MS - (JOURNAL.len() - i) as i64 * 90_000,
                priority: *priority,
                unit: (*unit).into(),
                ident: (*ident).into(),
                pid: Some(600 + i as u32),
                message: (*message).into(),
            })
            .collect(),
    }
}
