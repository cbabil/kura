//! Memory from `/proc/meminfo`, counted like `free` and `htop`.

use procfs_core::{FromBufRead, Meminfo};

use super::StatsError;
use crate::root::SysRoot;

/// Memory in bytes.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Memory {
    pub total: u64,
    /// In use by programs: total less free, buffers and reclaimable cache.
    pub used: u64,
    /// Buffers, page cache and reclaimable slab.
    pub cache: u64,
}

/// Reads `/proc/meminfo`.
///
/// # Errors
/// Fails when the file cannot be read or parsed.
pub fn read(root: &SysRoot) -> Result<Memory, StatsError> {
    let m = Meminfo::from_buf_read(std::io::BufReader::new(root.open("/proc/meminfo")?))?;
    let cache = m.buffers + m.cached + m.s_reclaimable.unwrap_or(0);
    let used = m.mem_total.saturating_sub(m.mem_free).saturating_sub(cache);
    Ok(Memory { total: m.mem_total, used, cache })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    #[test]
    fn reads_used_and_cache() {
        let f = Fixture::full();
        let m = read(&f.root()).unwrap();
        assert_eq!(m.total, 16_000_000 * 1024);
        assert_eq!(m.cache, 2_200_000 * 1024);
        assert_eq!(m.used, 5_800_000 * 1024);
    }

    #[test]
    fn errors_on_a_bad_file() {
        let f = Fixture::full();
        f.write("proc/meminfo", "MemTotal: x kB\n");
        assert!(read(&f.root()).is_err());
    }
}
