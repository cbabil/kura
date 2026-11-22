//! The user's trash, in the freedesktop layout other programs read too:
//! `~/.local/share/Trash/files/<name>` with `info/<name>.trashinfo` saying
//! where it was. Only the home's own volume: a file elsewhere is refused
//! as [`Failure::OtherVolume`], and the interface offers to delete it.

use std::fs;
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};

use kura_desktop_core::files::{Failure, MAX_ENTRIES, Trashed, percent_encode, valid_name};

use crate::{exists, io, modified, ops};

/// Names tried for one thing before giving up.
const MAX_SAME_NAME: usize = 1000;

/// A record longer than this is not one of ours.
const MAX_RECORD_BYTES: u64 = 16 * 1024;

pub struct Trash {
    root: PathBuf,
    files: PathBuf,
    info: PathBuf,
}

fn decode(text: &str) -> Option<String> {
    let mut bytes = Vec::with_capacity(text.len());
    let mut rest = text.as_bytes();
    while let [first, tail @ ..] = rest {
        if *first == b'%' {
            let hex = std::str::from_utf8(tail.get(..2)?).ok()?;
            bytes.push(u8::from_str_radix(hex, 16).ok()?);
            rest = &tail[2..];
        } else {
            bytes.push(*first);
            rest = tail;
        }
    }
    String::from_utf8(bytes).ok()
}

/// `secs` since 1970 as `YYYY-MM-DDThh:mm:ss`, in UTC.
fn stamp(secs: i64) -> String {
    let (days, of_day) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Days to a civil date (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let (era, doe) = (z.div_euclid(146_097), z.rem_euclid(146_097));
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let (day, month) = (doy - (153 * mp + 2) / 5 + 1, if mp < 10 { mp + 3 } else { mp - 9 });
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}", of_day / 3600, of_day % 3600 / 60, of_day % 60)
}

impl Trash {
    /// The trash of the user whose home folder is at `home`.
    pub fn new(home: &Path) -> Self {
        let trash = home.join(".local/share/Trash");
        Self { files: trash.join("files"), info: trash.join("info"), root: trash }
    }

    fn info_of(&self, name: &str) -> PathBuf {
        self.info.join(format!("{name}.trashinfo"))
    }

    /// Moves what is at `real` (which the user calls `path`) to the trash.
    pub fn put(&self, real: &Path, path: &str) -> Result<(), Failure> {
        let base = real.file_name().ok_or(Failure::Invalid)?.to_string_lossy().into_owned();
        // Not the trash's own, and not what holds the trash.
        if real.starts_with(&self.root) || self.root.starts_with(real) {
            return Err(Failure::Invalid);
        }
        io(real.symlink_metadata())?;
        for dir in [&self.files, &self.info] {
            io(fs::DirBuilder::new().recursive(true).mode(0o700).create(dir))?;
        }
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
        let record = format!(
            "[Trash Info]\nPath={}\nDeletionDate={}\n",
            percent_encode(path, "/-._~"),
            stamp(now.cast_signed())
        );
        // The record is made first and alone: its name is then ours.
        let name = (1..=MAX_SAME_NAME)
            .map(|n| if n == 1 { base.clone() } else { format!("{base}.{n}") })
            .filter(|name| !exists(&self.files.join(name)))
            .find_map(|name| {
                let made = fs::OpenOptions::new().write(true).create_new(true).open(self.info_of(&name));
                made.ok().map(|file| (name, file))
            });
        let Some((name, mut file)) = name else { return Err(Failure::Io) };
        let moved = io(std::io::Write::write_all(&mut file, record.as_bytes()))
            .and_then(|()| io(fs::rename(real, self.files.join(&name))));
        if moved.is_err() {
            let _ = fs::remove_file(self.info_of(&name));
        }
        moved
    }

    /// Where `name` was, from its record.
    fn origin(&self, name: &str) -> Result<String, Failure> {
        let mut record = String::new();
        let file = io(fs::File::open(self.info_of(name)))?;
        io(std::io::Read::read_to_string(&mut std::io::Read::take(file, MAX_RECORD_BYTES), &mut record))?;
        let path = record.lines().find_map(|l| l.strip_prefix("Path=")).and_then(decode);
        path.ok_or(Failure::Invalid)
    }

    /// What is in the trash, most recently put there first.
    pub fn list(&self) -> Result<Vec<Trashed>, Failure> {
        let Ok(records) = fs::read_dir(&self.info) else { return Ok(Vec::new()) };
        let mut found = Vec::new();
        for record in records.flatten().take(MAX_ENTRIES) {
            let file_name = record.file_name().to_string_lossy().into_owned();
            let Some(name) = file_name.strip_suffix(".trashinfo") else { continue };
            let (Ok(path), Ok(meta)) = (self.origin(name), self.files.join(name).symlink_metadata()) else { continue };
            let deleted = record.metadata().map_or(0, |m| modified(&m));
            let size = if meta.is_dir() { 0 } else { meta.len() };
            found.push(Trashed { name: name.to_owned(), path, dir: meta.is_dir(), size, deleted });
        }
        found.sort_by(|a, b| b.deleted.cmp(&a.deleted).then_with(|| a.name.cmp(&b.name)));
        Ok(found)
    }

    /// Puts `name` back where it was; `real` gives where that is here.
    pub fn restore(&self, name: &str, real: impl Fn(&str) -> Result<PathBuf, Failure>) -> Result<(), Failure> {
        if !valid_name(name) {
            return Err(Failure::Invalid);
        }
        let target = real(&self.origin(name)?)?;
        if exists(&target) {
            return Err(Failure::Exists);
        }
        io(fs::rename(self.files.join(name), &target))?;
        io(fs::remove_file(self.info_of(name)))
    }

    /// Removes everything in the trash for good. What cannot be removed
    /// does not keep the rest; the first refusal is the answer.
    pub fn empty(&self) -> Result<(), Failure> {
        let mut first = Ok(());
        for dir in [&self.files, &self.info] {
            let Ok(items) = fs::read_dir(dir) else { continue };
            for item in items.flatten() {
                let removed = ops::delete(&item.path());
                first = first.and(removed);
            }
        }
        first
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_survive_the_record_and_dates_are_civil() {
        let path = "/home/chris/été 100%/a=b\n.txt";
        assert_eq!(decode(&percent_encode(path, "/-._~")).as_deref(), Some(path));
        assert_eq!(decode("%zz"), None);
        assert_eq!(decode("%4"), None);
        assert_eq!(stamp(0), "1970-01-01T00:00:00");
        assert_eq!(stamp(951_782_400), "2000-02-29T00:00:00");
        assert_eq!(stamp(1_795_305_599), "2026-11-21T23:59:59");
    }
}
