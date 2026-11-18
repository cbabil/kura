//! Per-user preferences (theme, dock order, window geometry), validated
//! against the interface's `Prefs` shape and kept as one JSON file per uid.

use std::collections::BTreeMap;
use std::io;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// The largest preferences body accepted, in bytes.
pub const MAX_PREFS_BYTES: usize = 64 * 1024;
const MAX_ITEMS: usize = 64;
const MAX_ID_LEN: usize = 64;
const MAX_COORD: f64 = 100_000.0;

/// The light/dark choice.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Theme {
    Dark,
    Light,
    System,
}

/// Where a window sits, in CSS pixels.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WindowGeometry {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// One user's preferences, as `Prefs` in `desktop/web/src/api/types.ts`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    pub theme: Theme,
    /// "auto" (the browser's languages) or a language code such as "fr".
    #[serde(default = "auto")]
    pub language: String,
    pub dock: Vec<String>,
    pub windows: BTreeMap<String, WindowGeometry>,
}

/// Why preferences were refused or could not be kept.
#[derive(Debug, thiserror::Error)]
pub enum PrefsError {
    #[error("preferences are larger than {MAX_PREFS_BYTES} bytes")]
    TooLarge,
    #[error("preferences do not match the expected shape: {0}")]
    Shape(#[from] serde_json::Error),
    #[error("preferences are out of range: {0}")]
    Invalid(&'static str),
    #[error("preferences could not be stored: {0}")]
    Io(#[from] io::Error),
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= MAX_ID_LEN
        && id.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
}

fn auto() -> String {
    "auto".to_owned()
}

/// "auto", or a BCP 47 style code: 2-3 letters, optionally a region.
fn valid_language(lang: &str) -> bool {
    let mut parts = lang.split('-');
    let base = parts.next().unwrap_or("");
    let base_ok = (2..=3).contains(&base.len()) && base.chars().all(|c| c.is_ascii_lowercase());
    let rest_ok = parts.all(|p| (2..=8).contains(&p.len()) && p.chars().all(|c| c.is_ascii_alphanumeric()));
    lang == "auto" || (base_ok && rest_ok && lang.len() <= 16)
}

fn valid_geometry(g: &WindowGeometry) -> bool {
    let coords = [g.x, g.y, g.w, g.h];
    coords.iter().all(|v| v.is_finite() && v.abs() <= MAX_COORD) && g.w >= 0.0 && g.h >= 0.0
}

impl Prefs {
    /// Parses and validates a request body.
    ///
    /// # Errors
    /// [`PrefsError::TooLarge`], [`PrefsError::Shape`] or [`PrefsError::Invalid`].
    pub fn parse(body: &[u8]) -> Result<Self, PrefsError> {
        if body.len() > MAX_PREFS_BYTES {
            return Err(PrefsError::TooLarge);
        }
        let prefs: Self = serde_json::from_slice(body)?;
        prefs.validate()?;
        Ok(prefs)
    }

    fn validate(&self) -> Result<(), PrefsError> {
        if self.dock.len() > MAX_ITEMS || self.windows.len() > MAX_ITEMS {
            return Err(PrefsError::Invalid("too many items"));
        }
        if !self.dock.iter().chain(self.windows.keys()).all(|id| valid_id(id)) {
            return Err(PrefsError::Invalid("bad app id"));
        }
        if !valid_language(&self.language) {
            return Err(PrefsError::Invalid("bad language"));
        }
        if !self.windows.values().all(valid_geometry) {
            return Err(PrefsError::Invalid("bad window geometry"));
        }
        Ok(())
    }
}

/// Preferences on disk: `<dir>/<uid>.json`, written atomically, mode 0600.
#[derive(Debug, Clone)]
pub struct PrefsStore {
    dir: PathBuf,
}

impl PrefsStore {
    /// A store in `dir` (created on first save).
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    fn file(&self, uid: u32) -> PathBuf {
        self.dir.join(format!("{uid}.json"))
    }

    /// Loads a user's preferences; `None` when none are saved or the saved
    /// file no longer validates.
    ///
    /// # Errors
    /// Fails when the file exists but cannot be read.
    pub fn load(&self, uid: u32) -> Result<Option<Prefs>, PrefsError> {
        match std::fs::read(self.file(uid)) {
            Ok(bytes) => Ok(Prefs::parse(&bytes).ok()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Saves a user's preferences, replacing the old file in one rename.
    ///
    /// # Errors
    /// Fails when the directory or file cannot be written.
    pub fn save(&self, uid: u32, prefs: &Prefs) -> Result<(), PrefsError> {
        std::fs::create_dir_all(&self.dir)?;
        let tmp = self.dir.join(format!(".{uid}.json.tmp"));
        let body = serde_json::to_vec(prefs)?;
        write_private(&tmp, &body)?;
        std::fs::rename(&tmp, self.file(uid))?;
        Ok(())
    }
}

#[cfg(unix)]
fn write_private(path: &std::path::Path, body: &[u8]) -> io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(path)?;
    f.write_all(body)?;
    f.sync_all()
}

#[cfg(test)]
mod tests;
