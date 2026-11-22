//! In-memory sign-in sessions: 256-bit random ids that end after 12 hours
//! idle, at sign-out, or when desktopd restarts. The helper keeps its
//! tickets in the same kind of store ([`IdleStore`]).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// How long a session lives without a request.
pub const IDLE_TIMEOUT: Duration = Duration::from_secs(12 * 3600);
/// The most sessions kept at once; the oldest idle one goes first.
pub const MAX_SESSIONS: usize = 256;

/// Who a session belongs to.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct SessionUser {
    pub name: String,
    pub uid: u32,
    /// Member of `sudo` at sign-in, for what the interface offers. The
    /// helper checks membership again on every action.
    pub admin: bool,
}

/// A sign-in as desktopd keeps it: the user, and the helper's ticket that
/// proves the sign-in to the helper (never sent to the browser).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    pub user: SessionUser,
    pub ticket: String,
}

struct Entry<T> {
    value: T,
    created: Instant,
    last_seen: Instant,
}

/// Thread-safe store of values under random ids, each dropped after
/// [`IDLE_TIMEOUT`] without use, and at a maximum age when one is set.
pub struct IdleStore<T> {
    inner: Mutex<HashMap<String, Entry<T>>>,
    max_age: Option<Duration>,
}

/// desktopd's live sessions.
pub type SessionStore = IdleStore<Session>;

impl<T> Default for IdleStore<T> {
    fn default() -> Self {
        Self { inner: Mutex::new(HashMap::new()), max_age: None }
    }
}

/// A new random session id: 32 bytes from the OS, hex encoded.
///
/// # Panics
/// Panics when the OS has no randomness, since no safe id can be made then.
pub fn new_session_id() -> String {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).expect("the OS random source failed");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

impl<T: Clone> IdleStore<T> {
    /// Creates an empty store.
    pub fn new() -> Self {
        Self::default()
    }

    /// A store whose values also end `max_age` after they were created,
    /// used or not.
    pub fn with_max_age(max_age: Duration) -> Self {
        Self { max_age: Some(max_age), ..Self::default() }
    }

    fn live(&self, e: &Entry<T>, now: Instant) -> bool {
        now.duration_since(e.last_seen) < IDLE_TIMEOUT
            && self.max_age.is_none_or(|max| now.duration_since(e.created) < max)
    }

    /// Keeps `value` under a new random id and returns the id.
    pub fn create(&self, value: T, now: Instant) -> String {
        self.create_capped(value, now, usize::MAX, |_| false)
    }

    /// As [`IdleStore::create`], keeping at most `max` values that are
    /// `same` (one user's, say): the oldest of those go first, so one owner
    /// cannot push the others out.
    pub fn create_capped(&self, value: T, now: Instant, max: usize, same: impl Fn(&T) -> bool) -> String {
        let id = new_session_id();
        let mut map = self.lock();
        map.retain(|_, e| self.live(e, now));
        loop {
            let mut own: Vec<(&String, Instant)> =
                map.iter().filter(|(_, e)| same(&e.value)).map(|(k, e)| (k, e.last_seen)).collect();
            if own.len() < max {
                break;
            }
            own.sort_by_key(|(_, seen)| *seen);
            let oldest = own[0].0.clone();
            map.remove(&oldest);
        }
        if map.len() >= MAX_SESSIONS {
            let oldest = map.iter().min_by_key(|(_, e)| e.last_seen).map(|(k, _)| k.clone());
            if let Some(k) = oldest {
                map.remove(&k);
            }
        }
        map.insert(id.clone(), Entry { value, created: now, last_seen: now });
        id
    }

    /// Returns the value and marks it used, or `None` when the id is
    /// unknown or has been idle too long (it is then removed).
    pub fn touch(&self, id: &str, now: Instant) -> Option<T> {
        self.with_live(id, now, T::clone)
    }

    /// Marks a session used without copying its value; false when it has
    /// ended (and it is then removed).
    pub fn keep_alive(&self, id: &str, now: Instant) -> bool {
        self.with_live(id, now, |_| ()).is_some()
    }

    fn with_live<R>(&self, id: &str, now: Instant, f: impl FnOnce(&T) -> R) -> Option<R> {
        let mut map = self.lock();
        if !self.live(map.get(id)?, now) {
            map.remove(id);
            return None;
        }
        let entry = map.get_mut(id)?;
        entry.last_seen = now;
        Some(f(&entry.value))
    }

    /// Ends a session and returns its value; unknown ids give `None`.
    pub fn remove(&self, id: &str) -> Option<T> {
        self.lock().remove(id).map(|e| e.value)
    }

    /// Puts `value` back under the id it had (see [`IdleStore::remove`]).
    pub fn restore(&self, id: &str, value: T, now: Instant) {
        self.lock().insert(id.to_owned(), Entry { value, created: now, last_seen: now });
    }

    /// Ends every session whose value is `gone`; how many there were.
    pub fn remove_where(&self, gone: impl Fn(&T) -> bool) -> usize {
        let mut map = self.lock();
        let before = map.len();
        map.retain(|_, e| !gone(&e.value));
        before - map.len()
    }

    /// The number of sessions held, live or not yet pruned.
    pub fn len(&self) -> usize {
        self.lock().len()
    }

    /// True when no session is held.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Entry<T>>> {
        // A panic while holding the lock cannot leave the map inconsistent.
        self.inner.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests;
