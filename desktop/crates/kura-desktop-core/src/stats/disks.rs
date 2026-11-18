//! Space on mounted volumes: real file systems from `/proc/self/mountinfo`,
//! measured with `statvfs` behind [`FsUsage`] so tests need no real mounts.

use std::collections::HashSet;
use std::path::Path;

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

/// Lists real volumes once each (a bind mount of the same tree is skipped),
/// sorted by mount point. Volumes that cannot be measured are left out.
///
/// # Errors
/// Fails when mountinfo cannot be read or parsed.
pub fn read(root: &SysRoot, fs: &dyn FsUsage) -> Result<Vec<DiskUsage>, StatsError> {
    let file = std::io::BufReader::new(root.open("/proc/self/mountinfo")?);
    let mounts = MountInfos::from_buf_read(file)?;
    let mut seen = HashSet::new();
    let mut disks: Vec<DiskUsage> = mounts
        .into_iter()
        .filter(|m| REAL_FS.contains(&m.fs_type.as_str()))
        .filter(|m| seen.insert((m.majmin.clone(), m.root.clone())))
        .filter_map(|m| {
            let (used, size) = fs.usage(&root.path(&m.mount_point)).ok()?;
            Some(DiskUsage { mount: m.mount_point.to_string_lossy().into_owned(), used, size })
        })
        .take(MAX_DISKS)
        .collect();
    disks.sort_by(|a, b| a.mount.cmp(&b.mount));
    Ok(disks)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    struct Fake;
    impl FsUsage for Fake {
        fn usage(&self, path: &Path) -> std::io::Result<(u64, u64)> {
            if path.ends_with("srv") {
                return Err(std::io::Error::other("gone"));
            }
            Ok((path.as_os_str().len() as u64, 100))
        }
    }

    #[test]
    fn lists_real_volumes_once() {
        let f = Fixture::full();
        let disks = read(&f.root(), &Fake).unwrap();
        let mounts: Vec<&str> = disks.iter().map(|d| d.mount.as_str()).collect();
        assert_eq!(mounts, ["/", "/home"]);
        assert!(disks.iter().all(|d| d.size == 100));
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
        assert!(read(&f.root(), &Fake).is_err());
    }
}
