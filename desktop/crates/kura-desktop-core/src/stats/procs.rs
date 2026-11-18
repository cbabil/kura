//! The busiest processes, from `/proc/<pid>/stat` and `status`. CPU is the
//! change in ticks between two readings, so the first reading shows 0.

use std::collections::HashMap;

use procfs_core::FromRead;
use procfs_core::process::Stat;

use super::{Proc, USER_HZ, round1};
use crate::accounts::Accounts;
use crate::root::SysRoot;

/// How many processes are reported.
pub const TOP_PROCS: usize = 15;

/// Remembers each process's ticks between readings.
#[derive(Debug, Default)]
pub struct ProcTracker {
    prev: HashMap<i32, u64>,
}

struct Seen {
    pid: i32,
    name: String,
    cpu: f64,
    /// Resident pages from `stat`, only to rank before reading `status`.
    rss_pages: u64,
}

impl ProcTracker {
    /// Reads every process's `stat` and returns the [`TOP_PROCS`] busiest by
    /// CPU, then by memory; only those have their `status` read. `secs` is
    /// the time since the last reading.
    pub fn read(&mut self, root: &SysRoot, accounts: &Accounts, secs: f64) -> Vec<Proc> {
        let mut ticks = HashMap::with_capacity(self.prev.len());
        let mut seen: Vec<Seen> = pids(root)
            .filter_map(|pid| {
                let stat = Stat::from_read(root.open(format!("/proc/{pid}/stat")).ok()?).ok()?;
                let now = stat.utime + stat.stime;
                ticks.insert(pid, now);
                let delta = self.prev.get(&pid).map_or(0, |p| now.saturating_sub(*p));
                let cpu = if secs > 0.0 { delta as f64 * 100.0 / (secs * USER_HZ as f64) } else { 0.0 };
                Some(Seen { pid, name: stat.comm, cpu, rss_pages: stat.rss })
            })
            .collect();
        self.prev = ticks;
        seen.sort_by(|a, b| b.cpu.total_cmp(&a.cpu).then(b.rss_pages.cmp(&a.rss_pages)).then(a.pid.cmp(&b.pid)));
        seen.truncate(TOP_PROCS);
        seen.into_iter().filter_map(|s| with_status(root, accounts, s)).collect()
    }
}

fn with_status(root: &SysRoot, accounts: &Accounts, s: Seen) -> Option<Proc> {
    let status = root.read(format!("/proc/{}/status", s.pid)).ok()?;
    let (uid, rss_kb) = parse_status(&status)?;
    Some(Proc { pid: s.pid, name: s.name, user: accounts.name_of(uid), cpu: round1(s.cpu), mem: rss_kb * 1024 })
}

/// The real uid and `VmRSS` (kB, 0 for kernel threads) from `status`.
fn parse_status(text: &str) -> Option<(u32, u64)> {
    let field = |key: &str| text.lines().find_map(|l| l.strip_prefix(key)?.split_whitespace().next());
    let uid = field("Uid:")?.parse().ok()?;
    let rss = field("VmRSS:").and_then(|v| v.parse().ok()).unwrap_or(0);
    Some((uid, rss))
}

fn pids(root: &SysRoot) -> impl Iterator<Item = i32> {
    std::fs::read_dir(root.path("/proc"))
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.parse().ok())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    #[test]
    fn first_reading_ranks_by_memory() {
        let f = Fixture::full();
        let accounts = Accounts::load(&f.root());
        let procs = ProcTracker::default().read(&f.root(), &accounts, 0.0);
        let names: Vec<&str> = procs.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, ["dockerd", "kura-desktopd", "systemd", "kthreadd"]);
        assert_eq!(procs[1].user, "kura");
        assert_eq!(procs[1].mem, 28_000 * 1024);
        assert!(procs.iter().all(|p| p.cpu == 0.0));
    }

    #[test]
    fn second_reading_ranks_by_cpu_delta() {
        let f = Fixture::full();
        let accounts = Accounts::load(&f.root());
        let mut tracker = ProcTracker::default();
        tracker.read(&f.root(), &accounts, 2.0);
        f.proc(902, "kura-desktopd", 1000, 150, 150, 28000);
        f.proc(4000, "new", 0, 900, 0, 1);
        f.write("proc/7/stat", "broken");
        f.write("proc/8/stat", "8 (nostatus) S 1 8 8 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 1 1 1 1 0 0 0");
        let procs = tracker.read(&f.root(), &accounts, 2.0);
        assert_eq!((procs[0].pid, procs[0].cpu), (902, 100.0));
        assert_eq!(procs.iter().find(|p| p.pid == 4000).map(|p| p.cpu), Some(0.0));
    }

    #[test]
    fn keeps_only_the_busiest() {
        let f = Fixture::full();
        for pid in 100..130 {
            f.proc(pid, "worker", 0, 0, 0, pid as u64);
        }
        let procs = ProcTracker::default().read(&f.root(), &Accounts::default(), 2.0);
        assert_eq!(procs.len(), TOP_PROCS);
        assert_eq!(procs[0].user, "0");
    }
}
