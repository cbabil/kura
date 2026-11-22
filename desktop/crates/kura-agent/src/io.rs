//! A file's bytes, a piece at a time: a download reads pieces, an upload
//! writes them to a hidden file that takes its name with the last one.

use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

use kura_desktop_core::files::{CHUNK, Failure, part_name, valid_upload_id};

use crate::{exists, io};

/// The whole file's size, and up to [`CHUNK`] of its bytes from `offset`.
/// Only a regular file is read: it is opened without waiting (a pipe would
/// never open, or never end) and then looked at, so what is read is what
/// was checked.
pub fn read_chunk(path: &Path, offset: u64) -> Result<(u64, Vec<u8>), Failure> {
    let mut file = io(OpenOptions::new().read(true).custom_flags(libc::O_NONBLOCK | libc::O_NOCTTY).open(path))?;
    let meta = io(file.metadata())?;
    if !meta.is_file() {
        return Err(Failure::Invalid);
    }
    io(file.seek(SeekFrom::Start(offset)))?;
    let mut bytes = Vec::with_capacity(CHUNK.min(usize::try_from(meta.len()).unwrap_or(CHUNK)));
    io(file.take(CHUNK as u64).read_to_end(&mut bytes))?;
    Ok((meta.len(), bytes))
}

/// Where the upload `id` to `path` is kept until its last piece.
fn part_of(path: &Path, id: &str) -> Result<PathBuf, Failure> {
    if !valid_upload_id(id) {
        return Err(Failure::Invalid);
    }
    let name = path.file_name().ok_or(Failure::Invalid)?.to_string_lossy();
    Ok(path.with_file_name(part_name(&name, id)))
}

/// Writes the piece `data` of the new file `path`, which starts at
/// `offset`. Nothing that exists is written over.
pub fn write_chunk(path: &Path, id: &str, offset: u64, last: bool, data: &[u8]) -> Result<(), Failure> {
    if data.len() > CHUNK {
        return Err(Failure::Invalid);
    }
    let part = part_of(path, id)?;
    if exists(path) {
        return Err(Failure::Exists);
    }
    let made = offset == 0 && !exists(&part);
    let written =
        write_part(&part, offset, data).and_then(|()| if last { io(fs::rename(&part, path)) } else { Ok(()) });
    // Whatever went wrong, half a file is not left behind (but nothing that
    // was there before this upload is touched).
    if written.is_err() && (made || offset > 0) {
        let _ = fs::remove_file(&part);
    }
    written
}

/// Adds `data` to the part file, which must be `offset` bytes long so far.
/// The first piece makes the file, and only if nothing is there (a link
/// planted under that name is not followed).
fn write_part(part: &Path, offset: u64, data: &[u8]) -> Result<(), Failure> {
    let mut file = if offset == 0 {
        io(OpenOptions::new().write(true).create_new(true).open(part))?
    } else {
        let file = io(OpenOptions::new().append(true).custom_flags(libc::O_NOFOLLOW).open(part))?;
        // A piece out of order would make a file that is not the one sent.
        if io(file.metadata())?.len() != offset {
            return Err(Failure::Invalid);
        }
        file
    };
    io(file.write_all(data))
}
