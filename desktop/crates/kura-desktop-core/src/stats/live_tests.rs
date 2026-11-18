//! Readers against the live system. Linux only, and only when the CI job sets
//! `KURA_LIVE_TESTS=1`, since a developer's machine may differ.

use std::time::{Duration, Instant};

use super::collector::Collector;
use super::disks::Statvfs;
use super::system;
use crate::root::SysRoot;

#[test]
fn reads_the_real_proc_and_sys() {
    if std::env::var_os("KURA_LIVE_TESTS").is_none() {
        return;
    }
    let info = system::read(&SysRoot::default()).unwrap();
    assert!(info.cores > 0 && info.mem_total > 0 && info.uptime > 0, "{info:?}");
    assert!(!info.hostname.is_empty() && !info.kernel.is_empty());

    let mut c = Collector::new(SysRoot::default(), Box::new(Statvfs));
    let t0 = Instant::now();
    c.collect(0, t0).unwrap();
    std::thread::sleep(Duration::from_millis(500));
    let (sample, procs) = c.collect(500, Instant::now()).unwrap();
    assert!((0.0..=100.0).contains(&sample.cpu));
    assert!(sample.mem_used > 0 && sample.mem_used < sample.mem_total);
    assert!(sample.disks.iter().any(|d| d.mount == "/" && d.size > 0), "{:?}", sample.disks);
    assert!(!procs.is_empty() && procs.iter().any(|p| p.mem > 0));
    println!("live sample: {sample:?}\ntop process: {:?}", procs[0]);
}
