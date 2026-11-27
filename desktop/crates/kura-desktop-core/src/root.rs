//! A file-system root for `/proc`, `/sys` and `/etc`, so readers can be tested
//! against fixture trees instead of the live system.

use std::io;
use std::path::{Path, PathBuf};

/// Where absolute system paths are resolved: `/` in production, a fixture
/// directory in tests.
#[derive(Debug, Clone)]
pub struct SysRoot {
    base: PathBuf,
}

impl Default for SysRoot {
    fn default() -> Self {
        Self::new("/")
    }
}

impl SysRoot {
    /// Creates a root at `base`.
    pub fn new(base: impl Into<PathBuf>) -> Self {
        Self { base: base.into() }
    }

    /// Resolves an absolute system path such as `/proc/stat` under this root.
    pub fn path(&self, absolute: impl AsRef<Path>) -> PathBuf {
        let rel = absolute.as_ref().strip_prefix("/").unwrap_or(absolute.as_ref());
        self.base.join(rel)
    }

    /// Reads a whole file under this root.
    ///
    /// # Errors
    /// Fails when the file cannot be read; the error names the path.
    pub fn read(&self, absolute: impl AsRef<Path>) -> io::Result<String> {
        let path = self.path(absolute);
        std::fs::read_to_string(&path).map_err(|e| io::Error::new(e.kind(), format!("{}: {e}", path.display())))
    }

    /// True when this image has the unit `unit` and every one of `programs`:
    /// a feature whose packages may be left out (the local screen, Remote
    /// Desktop, the Browser).
    pub fn has_unit(&self, unit: &str, programs: &[&str]) -> bool {
        self.path(format!("/usr/lib/systemd/system/{unit}")).exists() && programs.iter().all(|p| self.path(p).exists())
    }

    /// Opens a file under this root for streaming parsers.
    ///
    /// # Errors
    /// Fails when the file cannot be opened.
    pub fn open(&self, absolute: impl AsRef<Path>) -> io::Result<std::fs::File> {
        std::fs::File::open(self.path(absolute))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_absolute_paths_under_the_base() {
        let root = SysRoot::new("/tmp/fixture");
        assert_eq!(root.path("/proc/stat"), PathBuf::from("/tmp/fixture/proc/stat"));
        assert_eq!(root.path("proc/stat"), PathBuf::from("/tmp/fixture/proc/stat"));
        assert_eq!(SysRoot::default().path("/etc"), PathBuf::from("/etc"));
    }

    #[test]
    fn a_unit_counts_only_with_its_programs() {
        let dir = tempfile::tempdir().unwrap();
        let root = SysRoot::new(dir.path());
        assert!(!root.has_unit("x.service", &[]));
        std::fs::create_dir_all(dir.path().join("usr/lib/systemd/system")).unwrap();
        std::fs::write(dir.path().join("usr/lib/systemd/system/x.service"), "").unwrap();
        assert!(root.has_unit("x.service", &[]));
        assert!(!root.has_unit("x.service", &["/usr/bin/x"]));
    }

    #[test]
    fn read_errors_name_the_path() {
        let err = SysRoot::new("/nonexistent-kura").read("/proc/stat").unwrap_err();
        assert!(err.to_string().contains("/nonexistent-kura/proc/stat"));
        assert!(SysRoot::new("/nonexistent-kura").open("/x").is_err());
    }
}
