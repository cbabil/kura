//! Network traffic from `/proc/net/dev`, summed over the device's own
//! interfaces (loopback and container bridges would count traffic twice).

use procfs_core::FromBufRead;
use procfs_core::net::InterfaceDeviceStatus;

use super::StatsError;
use crate::root::SysRoot;

/// Interface name prefixes left out of the totals.
const VIRTUAL: [&str; 7] = ["lo", "veth", "docker", "br-", "virbr", "cni", "flannel"];

/// Cumulative bytes received and sent.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct NetBytes {
    pub rx: u64,
    pub tx: u64,
}

/// Reads and sums `/proc/net/dev`.
///
/// # Errors
/// Fails when the file cannot be read or parsed.
pub fn read(root: &SysRoot) -> Result<NetBytes, StatsError> {
    let devs = InterfaceDeviceStatus::from_buf_read(std::io::BufReader::new(root.open("/proc/net/dev")?))?;
    let real = devs.0.values().filter(|d| !VIRTUAL.iter().any(|p| d.name.starts_with(p)));
    Ok(real.fold(NetBytes::default(), |acc, d| NetBytes { rx: acc.rx + d.recv_bytes, tx: acc.tx + d.sent_bytes }))
}

/// Bytes per second between two readings `secs` apart; a counter reset reads
/// as zero.
pub fn rates(prev: NetBytes, cur: NetBytes, secs: f64) -> (f64, f64) {
    if secs <= 0.0 {
        return (0.0, 0.0);
    }
    let rate = |a: u64, b: u64| b.saturating_sub(a) as f64 / secs;
    (rate(prev.rx, cur.rx), rate(prev.tx, cur.tx))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    #[test]
    fn sums_real_interfaces_only() {
        let f = Fixture::full();
        assert_eq!(read(&f.root()).unwrap(), NetBytes { rx: 1000, tx: 500 });
    }

    #[test]
    fn rates_between_readings() {
        let a = NetBytes { rx: 1000, tx: 100 };
        assert_eq!(rates(a, NetBytes { rx: 3000, tx: 300 }, 2.0), (1000.0, 100.0));
        assert_eq!(rates(a, NetBytes { rx: 10, tx: 10 }, 2.0), (0.0, 0.0));
        assert_eq!(rates(a, a, 0.0), (0.0, 0.0));
    }

    #[test]
    fn errors_when_missing() {
        let f = Fixture::full();
        std::fs::remove_file(f.dir.path().join("proc/net/dev")).unwrap();
        assert!(read(&f.root()).is_err());
    }
}
