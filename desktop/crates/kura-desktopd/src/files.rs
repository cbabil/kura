//! desktopd's end of the file agents (`kura-agent`, ADR-031): one socket
//! for each session that uses Files, opened by the helper the first time
//! and dropped when it breaks, when its ticket ends, or when it has not
//! been used for a while. Dropping the socket ends the agent.

mod frame;

use std::collections::HashMap;
use std::io;
use std::os::fd::OwnedFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use kura_desktop_core::files::{Reply, Request};
use kura_desktop_core::lock;
use tokio::net::UnixStream;

use self::frame::{receive, send};
use crate::helper::{Helper, HelperError};

/// How long the agent may take to answer what is quick by nature.
const ASK_TIMEOUT: Duration = Duration::from_secs(60);
/// ...and what moves as much as the user chose: a copy, a move, a deletion.
const WORK_TIMEOUT: Duration = Duration::from_secs(6 * 3600);
/// How long a new agent may take to say hello.
const HELLO_TIMEOUT: Duration = Duration::from_secs(10);
/// An agent nobody asked anything for this long is let go.
const IDLE: Duration = Duration::from_secs(600);
/// Listings built at once, over all sessions: each is a few megabytes for
/// a moment, and desktopd's memory is small.
const LISTINGS: usize = 4;

/// The socket to one user's agent.
pub struct FilesLink {
    /// The user's home folder, as the agent said.
    pub home: String,
    stream: tokio::sync::Mutex<UnixStream>,
    /// Set while an exchange is under way and left set when it does not
    /// finish (an error, a timeout, a request the browser gave up): the two
    /// ends then no longer agree on where a message starts, and the link
    /// must not be used again.
    broken: AtomicBool,
    used: Mutex<Instant>,
}

/// A reply and the bytes it says follow.
pub type Answer = (Reply, Option<Vec<u8>>);

impl FilesLink {
    /// Takes the socket the helper gave and asks the agent for the home.
    ///
    /// # Errors
    /// Fails when the socket cannot be used or the agent does not answer.
    pub async fn open(socket: OwnedFd) -> io::Result<Self> {
        let socket = std::os::unix::net::UnixStream::from(socket);
        socket.set_nonblocking(true)?;
        let mut link = Self {
            home: String::new(),
            stream: tokio::sync::Mutex::new(UnixStream::from_std(socket)?),
            broken: AtomicBool::new(false),
            used: Mutex::new(Instant::now()),
        };
        let hello = tokio::time::timeout(HELLO_TIMEOUT, link.ask(&Request::Hello, None)).await;
        let hello = hello.unwrap_or_else(|_| Err(io::ErrorKind::TimedOut.into()))?.0;
        link.home = hello.home.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "no home folder"))?;
        Ok(link)
    }

    /// Sends `request` (with `data` after a write) and waits for the reply
    /// and the bytes it says follow. Requests of one session take turns.
    ///
    /// # Errors
    /// Fails when the agent is gone, answers nonsense or takes too long;
    /// the link is then broken for good.
    pub async fn ask(&self, request: &Request, data: Option<&[u8]>) -> io::Result<Answer> {
        let mut stream = self.stream.lock().await;
        self.exchange(&mut stream, request, data).await
    }

    /// As [`FilesLink::ask`], but `None` at once when the agent is busy
    /// with another request (a long copy): for what is asked again anyway.
    ///
    /// # Errors
    /// As [`FilesLink::ask`].
    pub async fn ask_if_free(&self, request: &Request) -> io::Result<Option<Answer>> {
        let Ok(mut stream) = self.stream.try_lock() else { return Ok(None) };
        self.exchange(&mut stream, request, None).await.map(Some)
    }

    async fn exchange(&self, stream: &mut UnixStream, request: &Request, data: Option<&[u8]>) -> io::Result<Answer> {
        // Broken until proven whole: if this future is dropped half-way,
        // the reply stays unread and the next request must not take it.
        if self.broken.swap(true, Ordering::AcqRel) {
            return Err(io::Error::new(io::ErrorKind::BrokenPipe, "the link is broken"));
        }
        *lock(&self.used) = Instant::now();
        let long = matches!(
            request,
            Request::Copy { .. }
                | Request::Rename { .. }
                | Request::Delete { .. }
                | Request::Trash { .. }
                | Request::EmptyTrash
        );
        let talk = async {
            send(stream, &serde_json::to_vec(request).map_err(io::Error::other)?).await?;
            if let Some(data) = data {
                send(stream, data).await?;
            }
            let reply: Reply = serde_json::from_slice(&receive(stream).await?).map_err(io::Error::other)?;
            let bytes = if reply.data { Some(receive(stream).await?) } else { None };
            Ok((reply, bytes))
        };
        let limit = if long { WORK_TIMEOUT } else { ASK_TIMEOUT };
        let done = tokio::time::timeout(limit, talk).await.unwrap_or_else(|_| Err(io::ErrorKind::TimedOut.into()));
        if done.is_ok() {
            *lock(&self.used) = Instant::now();
            self.broken.store(false, Ordering::Release);
        }
        done
    }

    fn usable(&self, now: Instant) -> bool {
        !self.broken.load(Ordering::Acquire) && now.duration_since(*lock(&self.used)) < IDLE
    }
}

/// One session's place, held while its agent starts: one session never
/// starts two, and its slow start holds up nobody else.
#[derive(Default)]
struct Slot(tokio::sync::Mutex<Option<Arc<FilesLink>>>);

/// The links of the sessions that use Files, by session id.
pub struct Links {
    open: Mutex<HashMap<String, Arc<Slot>>>,
    /// See [`LISTINGS`].
    pub listings: tokio::sync::Semaphore,
}

impl Default for Links {
    fn default() -> Self {
        Self { open: Mutex::default(), listings: tokio::sync::Semaphore::new(LISTINGS) }
    }
}

impl Links {
    /// The place of `session`; on the way, links nobody uses are let go.
    fn slot(&self, session: &str) -> Arc<Slot> {
        let now = Instant::now();
        let mut open = lock(&self.open);
        open.retain(|id, slot| {
            // A place in use (locked, or held by a request) is left alone.
            id == session
                || Arc::strong_count(slot) > 1
                || slot.0.try_lock().is_ok_and(|l| l.as_ref().is_some_and(|l| l.usable(now)))
        });
        open.entry(session.to_owned()).or_default().clone()
    }

    /// The link of `session`, started through `helper` when there is none.
    /// The helper is asked each time whether `ticket` is still good: a
    /// sign-in that ended (a changed password, a removed account) loses
    /// its agent with the next request.
    ///
    /// # Errors
    /// The helper's refusal, or `Unavailable` when the agent does not answer.
    pub async fn get(&self, helper: &dyn Helper, session: &str, ticket: &str) -> Result<Arc<FilesLink>, HelperError> {
        let slot = self.slot(session);
        let mut held = slot.0.lock().await;
        if let Some(link) = held.take().filter(|link| link.usable(Instant::now())) {
            helper.keep_alive(ticket).await?;
            *held = Some(link.clone());
            return Ok(link);
        }
        let (_, socket) = helper.open_files(ticket).await?;
        let link = FilesLink::open(socket).await.map_err(|e| HelperError::Unavailable(format!("file agent: {e}")))?;
        let link = Arc::new(link);
        *held = Some(link.clone());
        Ok(link)
    }

    /// Drops the link of `session` (signed out).
    pub fn forget(&self, session: &str) {
        lock(&self.open).remove(session);
    }

    /// The number of sessions with a place here.
    pub fn len(&self) -> usize {
        lock(&self.open).len()
    }

    /// True when no session has one.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[cfg(test)]
mod tests;
