//! Device statistics for Activity Monitor: readers for `/proc` and `/sys`, a
//! collector that turns two readings into rates, history rings and the
//! 2-second sampler that feeds the `/api/stats` WebSocket.

pub mod collector;
pub mod cpu;
pub mod disks;
#[cfg(any(test, feature = "fixtures"))]
pub mod fixture;
pub mod history;
#[cfg(all(test, target_os = "linux"))]
mod live_tests;
pub mod mem;
pub mod net;
pub mod procs;
pub mod sampler;
pub mod system;
pub mod temp;

use serde::Serialize;

/// Space on one mounted volume, in bytes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DiskUsage {
    pub mount: String,
    pub used: u64,
    pub size: u64,
}

/// One measurement, as `Sample` in `desktop/web/src/api/types.ts`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Sample {
    /// Unix time in milliseconds.
    pub t: i64,
    /// 0..100 across all cores.
    pub cpu: f64,
    pub mem_used: u64,
    pub mem_cache: u64,
    pub mem_total: u64,
    /// Bytes per second.
    pub net_rx: f64,
    pub net_tx: f64,
    pub temp_c: Option<f64>,
    pub disks: Vec<DiskUsage>,
}

/// One of the busiest processes.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Proc {
    pub pid: i32,
    pub name: String,
    pub user: String,
    /// Percent of one core, like `top`.
    pub cpu: f64,
    /// Resident memory in bytes.
    pub mem: u64,
}

/// A reader could not read or parse its source.
#[derive(Debug, thiserror::Error)]
pub enum StatsError {
    #[error("stats source unreadable: {0}")]
    Io(#[from] std::io::Error),
    #[error("stats source malformed: {0}")]
    Parse(String),
}

impl From<procfs_core::ProcError> for StatsError {
    fn from(e: procfs_core::ProcError) -> Self {
        Self::Parse(e.to_string())
    }
}

/// `USER_HZ`: clock ticks per second in `/proc`, fixed at 100 by the kernel
/// ABI on every architecture Kura ships for.
pub const USER_HZ: u64 = 100;

/// The fixed facts procfs-core needs to parse `/proc/stat`.
struct ProcSystemInfo;

impl procfs_core::SystemInfoInterface for ProcSystemInfo {
    fn boot_time_secs(&self) -> procfs_core::ProcResult<u64> {
        Ok(0)
    }
    fn ticks_per_second(&self) -> u64 {
        USER_HZ
    }
    fn page_size(&self) -> u64 {
        4096
    }
    fn is_little_endian(&self) -> bool {
        cfg!(target_endian = "little")
    }
}

/// Rounds to one decimal, which is all the interface shows.
pub(crate) fn round1(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}
