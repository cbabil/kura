//! The file agent of Kura Desktop (ADR-031). It runs as the signed-in user,
//! so what it may read and change is what the kernel lets that user do; it
//! holds no rule of its own beyond the shape of a path. One request at a
//! time, read from and answered on one stream (`kura_desktop_core::files`).

mod io;
mod ops;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod tests_trash;
mod trash;

use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use kura_desktop_core::files::{Failure, Reply, Request, read_frame, valid_path, write_frame};

/// The agent of one user.
pub struct Agent {
    /// The user's home folder, as the user names it.
    home: String,
    /// Development only: the folder every path is taken under.
    jail: Option<PathBuf>,
}

/// A reply and the bytes that follow it, or why not.
type Done = Result<(Reply, Option<Vec<u8>>), Failure>;

impl Agent {
    /// The agent of the user whose home folder is `home`.
    pub fn new(home: String) -> Self {
        Self { home, jail: None }
    }

    /// For development: the same, with `/` standing for the folder `jail`.
    /// Only the path's text is kept inside; a link can lead out.
    pub fn jailed(home: String, jail: PathBuf) -> Self {
        Self { home, jail: Some(jail) }
    }

    /// Answers requests from `from` on `to` until `from` ends.
    ///
    /// # Errors
    /// Fails when the stream does, or a frame is not one.
    pub fn serve(&self, from: &mut impl Read, to: &mut impl Write) -> std::io::Result<()> {
        while let Some(frame) = read_frame(from)? {
            let request = serde_json::from_slice::<Request>(&frame);
            // A write's bytes always follow it, whatever becomes of it.
            let data = match &request {
                Ok(Request::Write { .. }) => read_frame(from)?.unwrap_or_default(),
                _ => Vec::new(),
            };
            let done = request.map_err(|_| Failure::Invalid).and_then(|r| self.handle(r, &data));
            let (reply, bytes) = done.unwrap_or_else(|why| (Reply::failed(why), None));
            write_frame(to, &serde_json::to_vec(&reply).map_err(std::io::Error::other)?)?;
            if let Some(bytes) = bytes {
                write_frame(to, &bytes)?;
            }
        }
        Ok(())
    }

    /// Where `path` is on this machine.
    fn real(&self, path: &str) -> Result<PathBuf, Failure> {
        if !valid_path(path) {
            return Err(Failure::Invalid);
        }
        Ok(match &self.jail {
            Some(jail) => jail.join(path.trim_start_matches('/')),
            None => PathBuf::from(path),
        })
    }

    fn trash(&self) -> Result<trash::Trash, Failure> {
        Ok(trash::Trash::new(&self.real(&self.home)?))
    }

    fn handle(&self, request: Request, data: &[u8]) -> Done {
        let plain = |done: Result<(), Failure>| done.map(|()| (Reply::default(), None));
        match request {
            Request::Hello => Ok((Reply { home: Some(self.home.clone()), ..Reply::default() }, None)),
            Request::List { path } => ops::list(&self.real(&path)?).map(|reply| (reply, None)),
            Request::MakeDir { path } => plain(ops::make_dir(&self.real(&path)?)),
            Request::Rename { from, to } => plain(ops::rename(&self.real(&from)?, &self.real(&to)?)),
            Request::Copy { from, to } => plain(ops::copy(&self.real(&from)?, &self.real(&to)?)),
            Request::Delete { path } => plain(ops::delete(&self.real(&path)?)),
            Request::Read { path, offset } => {
                let (size, bytes) = io::read_chunk(&self.real(&path)?, offset)?;
                Ok((Reply { size: Some(size), data: true, ..Reply::default() }, Some(bytes)))
            }
            Request::Write { path, id, offset, last } => {
                plain(io::write_chunk(&self.real(&path)?, &id, offset, last, data))
            }
            Request::Trash { path } => plain(self.trash()?.put(&self.real(&path)?, &path)),
            Request::ListTrash => {
                let trash = self.trash()?.list()?;
                Ok((Reply { trash: Some(trash), ..Reply::default() }, None))
            }
            Request::Restore { name } => plain(self.trash()?.restore(&name, |path| self.real(path))),
            Request::EmptyTrash => plain(self.trash()?.empty()),
        }
    }
}

/// What an I/O error is to the one who asked.
fn failure(e: &std::io::Error) -> Failure {
    use std::io::ErrorKind as K;
    match e.kind() {
        K::NotFound => Failure::NotFound,
        K::PermissionDenied | K::ReadOnlyFilesystem => Failure::Denied,
        K::AlreadyExists | K::DirectoryNotEmpty => Failure::Exists,
        K::CrossesDevices => Failure::OtherVolume,
        K::NotADirectory | K::IsADirectory | K::InvalidInput | K::InvalidFilename => Failure::Invalid,
        _ => Failure::Io,
    }
}

/// Runs `work`, turning an I/O error into its [`Failure`].
fn io<T>(work: std::io::Result<T>) -> Result<T, Failure> {
    work.map_err(|e| failure(&e))
}

/// True when something is at `path`, a dangling link included.
fn exists(path: &Path) -> bool {
    path.symlink_metadata().is_ok()
}

/// Seconds since 1970 of a file's last change (0 when it cannot be told).
fn modified(meta: &std::fs::Metadata) -> i64 {
    let since = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok());
    since.map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX))
}
