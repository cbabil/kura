//! Static facts about the device for `GET /api/system`.

use procfs_core::{FromRead, Uptime};
use serde::Serialize;

use super::{StatsError, cpu, mem};
use crate::root::SysRoot;

/// As `SystemInfo` in `desktop/web/src/api/types.ts`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    pub hostname: String,
    pub os: String,
    pub kernel: String,
    pub arch: String,
    pub cores: usize,
    pub mem_total: u64,
    /// Seconds since boot.
    pub uptime: u64,
    /// Whether the shared Browser can run here (ADR-036).
    pub browser: bool,
}

/// Reads the system facts.
///
/// # Errors
/// Fails when `/proc/stat`, `/proc/meminfo` or `/proc/uptime` is unreadable.
pub fn read(root: &SysRoot) -> Result<SystemInfo, StatsError> {
    let line = |p: &str| root.read(p).map(|s| s.trim().to_owned()).unwrap_or_default();
    let uptime = Uptime::from_read(root.open("/proc/uptime")?)?;
    let arch = Some(line("/proc/sys/kernel/arch")).filter(|a| !a.is_empty());
    Ok(SystemInfo {
        hostname: line("/proc/sys/kernel/hostname"),
        os: os_name(&root.read("/etc/os-release").unwrap_or_default()),
        kernel: line("/proc/sys/kernel/osrelease"),
        arch: arch.unwrap_or_else(|| std::env::consts::ARCH.to_owned()),
        cores: cpu::read(root)?.1,
        mem_total: mem::read(root)?.total,
        uptime: uptime.uptime as u64,
        browser: crate::browser::available(root),
    })
}

/// `PRETTY_NAME` from os-release, else `NAME`, else "Kura".
fn os_name(text: &str) -> String {
    let field = |key: &str| {
        text.lines()
            .find_map(|l| l.strip_prefix(key)?.strip_prefix('='))
            .map(|v| v.trim().trim_matches('"').to_owned())
            .filter(|v| !v.is_empty())
    };
    field("PRETTY_NAME").or_else(|| field("NAME")).unwrap_or_else(|| "Kura".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    #[test]
    fn reads_the_facts() {
        let f = Fixture::full();
        let s = read(&f.root()).unwrap();
        let want = SystemInfo {
            hostname: "kura-nuc".into(),
            os: "Kura 0.6.0".into(),
            kernel: "6.12.48-amd64".into(),
            arch: "x86_64".into(),
            cores: 2,
            mem_total: 16_000_000 * 1024,
            uptime: 273_600,
            browser: false,
        };
        assert_eq!(s, want);
        for file in crate::browser::files() {
            f.write(file.trim_start_matches('/'), "");
        }
        assert!(read(&f.root()).unwrap().browser, "a PC with the Browser's packages");
    }

    #[test]
    fn falls_back_when_optional_files_are_missing() {
        let f = Fixture::full();
        std::fs::remove_file(f.dir.path().join("proc/sys/kernel/arch")).unwrap();
        std::fs::remove_file(f.dir.path().join("etc/os-release")).unwrap();
        let s = read(&f.root()).unwrap();
        assert_eq!((s.os.as_str(), s.arch.as_str()), ("Kura", std::env::consts::ARCH));
        f.write("proc/uptime", "x\n");
        assert!(read(&f.root()).is_err());
    }

    #[test]
    fn os_name_prefers_pretty_name() {
        assert_eq!(os_name("NAME=Kura\n"), "Kura");
        assert_eq!(os_name("PRETTY_NAME=\"\"\nNAME=\"Debian\"\n"), "Debian");
    }
}
