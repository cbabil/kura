//! CPU use from the first line of `/proc/stat`.

use procfs_core::{FromBufReadSI, KernelStats};

use super::{ProcSystemInfo, StatsError};
use crate::root::SysRoot;

/// Cumulative CPU ticks across all cores.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CpuTicks {
    pub busy: u64,
    pub total: u64,
}

/// Reads total ticks and the number of cores.
///
/// # Errors
/// Fails when `/proc/stat` cannot be read or parsed.
pub fn read(root: &SysRoot) -> Result<(CpuTicks, usize), StatsError> {
    let file = std::io::BufReader::new(root.open("/proc/stat")?);
    let stats = KernelStats::from_buf_read(file, &ProcSystemInfo)?;
    let t = &stats.total;
    let idle = t.idle + t.iowait.unwrap_or(0);
    let total = t.user + t.nice + t.system + idle + t.irq.unwrap_or(0) + t.softirq.unwrap_or(0) + t.steal.unwrap_or(0);
    Ok((CpuTicks { busy: total - idle, total }, stats.cpu_time.len()))
}

/// Percent busy between two readings, 0..100.
pub fn usage(prev: CpuTicks, cur: CpuTicks) -> f64 {
    let total = cur.total.saturating_sub(prev.total);
    if total == 0 {
        return 0.0;
    }
    let busy = cur.busy.saturating_sub(prev.busy) as f64;
    (busy * 100.0 / total as f64).clamp(0.0, 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    #[test]
    fn reads_ticks_and_cores() {
        let f = Fixture::full();
        let (ticks, cores) = read(&f.root()).unwrap();
        assert_eq!(ticks, CpuTicks { busy: 1500, total: 10000 });
        assert_eq!(cores, 2);
    }

    #[test]
    fn usage_between_readings() {
        let a = CpuTicks { busy: 100, total: 1000 };
        let cases = [
            (CpuTicks { busy: 150, total: 1200 }, 25.0),
            (a, 0.0),
            (CpuTicks { busy: 50, total: 1100 }, 0.0),
            (CpuTicks { busy: 400, total: 1100 }, 100.0),
        ];
        for (cur, want) in cases {
            assert_eq!(usage(a, cur), want, "{cur:?}");
        }
    }

    #[test]
    fn errors_on_missing_or_bad_files() {
        let f = Fixture::full();
        f.write("proc/stat", "garbage\n");
        assert!(matches!(read(&f.root()), Err(StatsError::Parse(_))));
        std::fs::remove_file(f.dir.path().join("proc/stat")).unwrap();
        assert!(matches!(read(&f.root()), Err(StatsError::Io(_))));
    }
}
