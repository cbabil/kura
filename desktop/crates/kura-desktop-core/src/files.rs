//! Files: what `kura-desktopd` asks of `kura-agent`, the small program that
//! runs as the signed-in user so the kernel, not Kura, decides what they may
//! read and change (ADR-031). Messages are frames on a socket: a JSON
//! [`Request`] or [`Reply`], with a raw frame of bytes after a `write`
//! request and after a reply that says `data`.

mod frame;
#[cfg(test)]
mod tests;

pub use frame::{MAX_FRAME, read_frame, write_frame};
use serde::{Deserialize, Serialize};

/// The most bytes of a file one `read` or `write` carries.
pub const CHUNK: usize = 256 * 1024;
/// The most entries one listing gives; a longer folder says `truncated`.
pub const MAX_ENTRIES: usize = 5_000;
/// The most bytes of names one listing gives, so its reply always fits a frame.
pub const MAX_LIST_BYTES: usize = 512 * 1024;

/// One thing the agent is asked to do. Paths are absolute.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Request {
    /// The user's home folder.
    Hello,
    List {
        path: String,
    },
    MakeDir {
        path: String,
    },
    /// Renames or moves; never onto something that exists.
    Rename {
        from: String,
        to: String,
    },
    /// Copies a file or a folder with all in it; never onto something that exists.
    Copy {
        from: String,
        to: String,
    },
    /// Removes for good.
    Delete {
        path: String,
    },
    /// Up to [`CHUNK`] bytes of a file from `offset`; the bytes follow the reply.
    Read {
        path: String,
        offset: u64,
    },
    /// The next bytes of a new file (they follow the request). The file
    /// appears under its name with the `last` piece. `id` names this
    /// upload, so two of the same name do not mix.
    Write {
        path: String,
        id: String,
        offset: u64,
        last: bool,
    },
    /// Moves to the user's trash.
    Trash {
        path: String,
    },
    ListTrash,
    /// Puts `name` (as the trash calls it) back where it was.
    Restore {
        name: String,
    },
    EmptyTrash,
}

/// Why the agent did not do it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Failure {
    NotFound,
    /// The user may not: the kernel said no.
    Denied,
    Exists,
    /// Not a path or a name, or not a file where one is needed.
    Invalid,
    /// The trash is on another volume than the file.
    OtherVolume,
    Io,
}

/// One entry of a folder.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    pub name: String,
    /// A folder, or a link to one.
    pub dir: bool,
    pub link: bool,
    pub size: u64,
    /// Last change, in seconds since 1970.
    pub modified: i64,
}

/// One thing in the trash.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Trashed {
    /// Its name in the trash, which [`Request::Restore`] takes.
    pub name: String,
    /// Where it was.
    pub path: String,
    pub dir: bool,
    pub size: u64,
    /// When it was put there, in seconds since 1970.
    pub deleted: i64,
}

/// The agent's answer: `error`, or whichever fields the request fills.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reply {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<Failure>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub home: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub entries: Option<Vec<Entry>>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub truncated: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trash: Option<Vec<Trashed>>,
    /// The whole file's size (a `read`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    /// A frame of bytes follows.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub data: bool,
}

impl Reply {
    /// The reply that says why not.
    pub fn failed(why: Failure) -> Self {
        Self { error: Some(why), ..Self::default() }
    }
}

/// An absolute path with nothing to resolve: no `.` or `..` parts, no empty
/// ones but the root's, no NUL, 4096 bytes at most.
pub fn valid_path(path: &str) -> bool {
    let Some(rest) = path.strip_prefix('/') else { return false };
    path.len() <= 4096 && (rest.is_empty() || rest.split('/').all(valid_name))
}

/// One name in a folder: not empty, not `.` or `..`, no `/` or NUL, 255
/// bytes at most.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 255 && name != "." && name != ".." && !name.contains(['/', '\0'])
}

/// The hidden name the upload `id` of `name` is kept under until it is whole.
pub fn part_name(name: &str, id: &str) -> String {
    format!(".{name}.{id}.kura-upload")
}

/// An upload's id: 1 to 32 letters and digits.
pub fn valid_upload_id(id: &str) -> bool {
    (1..=32).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// `text` with every byte but letters, digits and those of `keep` as `%XX`.
pub fn percent_encode(text: &str, keep: &str) -> String {
    let plain = |b: u8| b.is_ascii_alphanumeric() || keep.as_bytes().contains(&b);
    text.bytes().map(|b| if plain(b) { char::from(b).to_string() } else { format!("%{b:02X}") }).collect()
}

/// The folder `path` is in and its own name; `None` for the root.
pub fn split(path: &str) -> Option<(&str, &str)> {
    let (parent, name) = path.rsplit_once('/')?;
    (!name.is_empty()).then_some((if parent.is_empty() { "/" } else { parent }, name))
}
