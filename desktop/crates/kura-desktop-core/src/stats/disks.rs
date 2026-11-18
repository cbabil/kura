//! Space on mounted volumes: real file systems from `/proc/self/mountinfo`,
//! measured with `statvfs` behind [`FsUsage`] so tests need no real mounts.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use procfs_core::FromBufRead;
use procfs_core::process::MountInfos;

use super::{DiskUsage, StatsError};
use crate::root::SysRoot;

/// File systems that hold user data; tmpfs, overlay and the like are left out.
const REAL_FS: [&str; 12] =
    ["ext2", "ext3", "ext4", "xfs", "btrfs", "vfat", "exfat", "ntfs", "ntfs3", "f2fs", "zfs", "fuseblk"];
/// The most volumes reported.
const MAX_DISKS: usize = 16;

/// Measures a mounted file system.
pub trait FsUsage: Send + Sync {
    /// Returns `(used, size)` in bytes for the file system at `path`.
    ///
    /// # Errors
    /// Fails when the file system cannot be queried.
    fn usage(&self, path: &Path) -> std::io::Result<(u64, u64)>;
}

/// The live system's `statvfs`.
#[derive(Debug, Default)]
pub struct Statvfs;

impl FsUsage for Statvfs {
    fn usage(&self, path: &Path) -> std::io::Result<(u64, u64)> {
        let s = rustix::fs::statvfs(path)?;
        let block = s.f_frsize;
        Ok((s.f_blocks.saturating_sub(s.f_bfree) * block, s.f_blocks * block))
    }
}

/// The mount points of real volumes, once each (a bind mount of the same
/// tree is skipped), sorted. Mounts change rarely, so callers keep the list.
///
/// # Errors
/// Fails when mountinfo cannot be read or parsed.
pub fn mounts(root: &SysRoot) -> Result<Vec<PathBuf>, StatsError> {
    let file = std::io::BufReader::new(root.open("/proc/self/mountinfo")?);
    let mut seen = HashSet::new();
    let mut points: Vec<PathBuf> = MountInfos::from_buf_read(file)?
        .into_iter()
        .filter(|m| REAL_FS.contains(&m.fs_type.as_str()))
        .filter(|m| seen.insert((m.majmin.clone(), m.root.clone())))
        .map(|m| m.mount_point)
        .take(MAX_DISKS)
        .collect();
    points.sort();
    Ok(points)
}

/// Measures each mount point; one that cannot be measured is left out.
pub fn usage(root: &SysRoot, fs: &dyn FsUsage, mounts: &[PathBuf]) -> Vec<DiskUsage> {
    mounts
        .iter()
        .filter_map(|m| {
            let (used, size) = fs.usage(&root.path(m)).ok()?;
            Some(DiskUsage { mount: m.to_string_lossy().into_owned(), used, size })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::{FakeFs, Fixture};

    #[test]
    fn lists_real_volumes_once() {
        let f = Fixture::full();
        let disks = usage(&f.root(), &FakeFs, &mounts(&f.root()).unwrap());
        let mounts: Vec<&str> = disks.iter().map(|d| d.mount.as_str()).collect();
        assert_eq!(mounts, ["/", "/home"]);
        assert!(disks.iter().all(|d| d.size == 100));
        assert!(usage(&f.root(), &FakeFs, &["/srv".into()]).is_empty(), "unmeasurable");
    }

    #[test]
    fn statvfs_measures_a_real_directory() {
        let dir = tempfile::tempdir().unwrap();
        let (used, size) = Statvfs.usage(dir.path()).unwrap();
        assert!(size > 0 && used <= size);
        assert!(Statvfs.usage(Path::new("/nonexistent-kura")).is_err());
    }

    #[test]
    fn errors_on_bad_mountinfo() {
        let f = Fixture::full();
        f.write("proc/self/mountinfo", "nonsense\n");
        assert!(mounts(&f.root()).is_err());
    }
}
