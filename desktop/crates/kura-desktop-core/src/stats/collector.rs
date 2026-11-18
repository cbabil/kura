//! Turns readings of `/proc` and `/sys` into a [`Sample`] and the busiest
//! processes. Rates come from the change since the previous call.

use std::time::Instant;

use super::cpu::{self, CpuTicks};
use super::disks::{self, FsUsage};
use super::net::{self, NetBytes};
use super::procs::ProcTracker;
use super::{Proc, Sample, StatsError, mem, round1, temp};
use crate::accounts::Accounts;
use crate::root::SysRoot;

/// Reads the system on demand, keeping what rates need between calls.
pub struct Collector {
    root: SysRoot,
    fs: Box<dyn FsUsage>,
    accounts: Accounts,
    prev: Option<(Instant, CpuTicks, NetBytes)>,
    procs: ProcTracker,
}

impl Collector {
    /// A collector reading under `root` and measuring volumes with `fs`.
    pub fn new(root: SysRoot, fs: Box<dyn FsUsage>) -> Self {
        let accounts = Accounts::load(&root);
        Self { root, fs, accounts, prev: None, procs: ProcTracker::default() }
    }

    /// Reloads user names, which change rarely.
    pub fn reload_accounts(&mut self) {
        self.accounts = Accounts::load(&self.root);
    }

    /// Takes one sample at Unix time `t` (ms) and monotonic time `now`.
    ///
    /// # Errors
    /// Fails when CPU or memory cannot be read; the other sources degrade to
    /// zero or empty instead.
    pub fn collect(&mut self, t: i64, now: Instant) -> Result<(Sample, Vec<Proc>), StatsError> {
        let (ticks, _) = cpu::read(&self.root)?;
        let memory = mem::read(&self.root)?;
        let bytes = net::read(&self.root).unwrap_or_default();
        let (secs, cpu, (rx, tx)) = match self.prev {
            Some((at, prev_ticks, prev_bytes)) => {
                let secs = now.duration_since(at).as_secs_f64();
                (secs, cpu::usage(prev_ticks, ticks), net::rates(prev_bytes, bytes, secs))
            }
            None => (0.0, 0.0, (0.0, 0.0)),
        };
        self.prev = Some((now, ticks, bytes));
        let sample = Sample {
            t,
            cpu: round1(cpu),
            mem_used: memory.used,
            mem_cache: memory.cache,
            mem_total: memory.total,
            net_rx: rx.round(),
            net_tx: tx.round(),
            temp_c: temp::read(&self.root),
            disks: disks::read(&self.root, self.fs.as_ref()).unwrap_or_default(),
        };
        let procs = self.procs.read(&self.root, &self.accounts, secs);
        Ok((sample, procs))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;
    use std::path::Path;
    use std::time::Duration;

    struct Fake;
    impl FsUsage for Fake {
        fn usage(&self, _: &Path) -> std::io::Result<(u64, u64)> {
            Ok((5, 10))
        }
    }

    #[test]
    fn two_readings_give_rates() {
        let f = Fixture::full();
        let mut c = Collector::new(f.root(), Box::new(Fake));
        let t0 = Instant::now();
        let (first, procs) = c.collect(1_000, t0).unwrap();
        assert_eq!((first.cpu, first.net_rx), (0.0, 0.0));
        assert_eq!(first.temp_c, Some(51.3));
        assert_eq!(first.disks.len(), 3);
        assert!(!procs.is_empty());
        f.write("proc/stat", &crate::stats::fixture::STAT.replacen("cpu  1000 0 500 8000", "cpu  1100 0 500 8300", 1));
        f.write("proc/net/dev", &crate::stats::fixture::NET_DEV.replace("eth0: 1000", "eth0: 5000"));
        c.reload_accounts();
        let (second, _) = c.collect(3_000, t0 + Duration::from_secs(2)).unwrap();
        assert_eq!((second.cpu, second.net_rx, second.net_tx), (25.0, 2000.0, 0.0));
        assert_eq!(second.mem_total, 16_000_000 * 1024);
    }

    #[test]
    fn missing_core_sources_fail_and_optional_ones_degrade() {
        let f = Fixture::full();
        std::fs::remove_file(f.dir.path().join("proc/net/dev")).unwrap();
        std::fs::remove_file(f.dir.path().join("proc/self/mountinfo")).unwrap();
        let mut c = Collector::new(f.root(), Box::new(Fake));
        let (s, _) = c.collect(0, Instant::now()).unwrap();
        assert!(s.disks.is_empty());
        std::fs::remove_file(f.dir.path().join("proc/meminfo")).unwrap();
        assert!(c.collect(0, Instant::now()).is_err());
    }
}
