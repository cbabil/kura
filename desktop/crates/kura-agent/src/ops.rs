//! Folders: listing, making, renaming, copying, deleting.

use std::fs;
use std::path::{Path, PathBuf};

use kura_desktop_core::files::{Entry, Failure, MAX_ENTRIES, MAX_LIST_BYTES, Reply};

use crate::{exists, io, modified};

/// The entries of the folder `dir`, at most [`MAX_ENTRIES`] and
/// [`MAX_LIST_BYTES`] of names.
pub fn list(dir: &Path) -> Result<Reply, Failure> {
    let mut entries = Vec::new();
    let (mut truncated, mut bytes) = (false, 0);
    for item in io(fs::read_dir(dir))? {
        let item = io(item)?;
        bytes += item.file_name().len();
        if entries.len() == MAX_ENTRIES || bytes > MAX_LIST_BYTES {
            truncated = true;
            break;
        }
        // Gone between the listing and the look: left out.
        let Ok(own) = item.metadata() else { continue };
        let link = own.is_symlink();
        // What a link leads to says whether it opens as a folder.
        let meta = if link { fs::metadata(item.path()).unwrap_or(own) } else { own };
        entries.push(Entry {
            name: item.file_name().to_string_lossy().into_owned(),
            dir: meta.is_dir(),
            link,
            size: if meta.is_dir() { 0 } else { meta.len() },
            modified: modified(&meta),
        });
    }
    Ok(Reply { entries: Some(entries), truncated, ..Reply::default() })
}

pub fn make_dir(path: &Path) -> Result<(), Failure> {
    io(fs::create_dir(path))
}

/// Renames or moves `from` to `to`, to another volume by copying. What
/// cannot be copied (a socket, a device) stops the move before anything is
/// removed.
pub fn rename(from: &Path, to: &Path) -> Result<(), Failure> {
    if exists(to) {
        return Err(Failure::Exists);
    }
    match io(fs::rename(from, to)) {
        Err(Failure::OtherVolume) => {
            copy_all(from, to, true)?;
            delete(from)
        }
        done => done,
    }
}

/// Copies a file, or a folder with all in it. Links are copied as links;
/// sockets and devices are left out.
pub fn copy(from: &Path, to: &Path) -> Result<(), Failure> {
    copy_all(from, to, false)
}

/// The copy; `whole` refuses what cannot be copied instead of leaving it
/// out. A copy that fails takes away what it had made.
fn copy_all(from: &Path, to: &Path, whole: bool) -> Result<(), Failure> {
    if exists(to) {
        return Err(Failure::Exists);
    }
    if to.starts_with(from) {
        return Err(Failure::Invalid);
    }
    io(from.symlink_metadata())?;
    let done = copy_tree(from, to, whole);
    if done.is_err() {
        let _ = delete(to);
    }
    done
}

fn copy_tree(from: &Path, to: &Path, whole: bool) -> Result<(), Failure> {
    let mut todo: Vec<(PathBuf, PathBuf)> = vec![(from.to_owned(), to.to_owned())];
    // Folders get their own rights last: one that may not be written to
    // could not be filled.
    let mut folders = Vec::new();
    while let Some((source, target)) = todo.pop() {
        let meta = io(source.symlink_metadata())?;
        if meta.is_symlink() {
            io(std::os::unix::fs::symlink(io(fs::read_link(&source))?, &target))?;
        } else if meta.is_dir() {
            io(fs::create_dir(&target))?;
            for item in io(fs::read_dir(&source))? {
                let item = io(item)?;
                todo.push((item.path(), target.join(item.file_name())));
            }
            folders.push((target, meta.permissions()));
        } else if meta.is_file() {
            io(fs::copy(&source, &target))?;
        } else if whole {
            return Err(Failure::Invalid);
        }
    }
    for (folder, rights) in folders.into_iter().rev() {
        io(fs::set_permissions(folder, rights))?;
    }
    Ok(())
}

/// Removes a file, a link, or a folder with all in it, for good. A folder
/// the user closed to themself is opened again first.
pub fn delete(path: &Path) -> Result<(), Failure> {
    let meta = io(path.symlink_metadata())?;
    if !meta.is_dir() {
        return io(fs::remove_file(path));
    }
    match io(fs::remove_dir_all(path)) {
        Err(Failure::Denied) => {
            open_up(path);
            io(fs::remove_dir_all(path))
        }
        done => done,
    }
}

/// Gives the owner every right on the folders under `path` (their own
/// read-only folders could otherwise never be emptied).
fn open_up(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let mut todo = vec![path.to_owned()];
    while let Some(folder) = todo.pop() {
        let _ = fs::set_permissions(&folder, fs::Permissions::from_mode(0o700));
        let Ok(items) = fs::read_dir(&folder) else { continue };
        todo.extend(items.flatten().filter(|i| i.file_type().is_ok_and(|t| t.is_dir())).map(|i| i.path()));
    }
}
