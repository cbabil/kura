//! In-memory sign-in sessions: 256-bit random ids that end after 12 hours
//! idle, at sign-out, or when desktopd restarts.

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
    /// Member of `sudo`; kept for D2, where admin actions arrive.
    pub admin: bool,
}

struct Entry {
    user: SessionUser,
    last_seen: Instant,
}

/// Thread-safe store of live sessions.
#[derive(Default)]
pub struct SessionStore {
    inner: Mutex<HashMap<String, Entry>>,
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

impl SessionStore {
    /// Creates an empty store.
    pub fn new() -> Self {
        Self::default()
    }

    /// Starts a session for `user` and returns its id.
    pub fn create(&self, user: SessionUser, now: Instant) -> String {
        let id = new_session_id();
        let mut map = self.lock();
        map.retain(|_, e| now.duration_since(e.last_seen) < IDLE_TIMEOUT);
        if map.len() >= MAX_SESSIONS {
            let oldest = map.iter().min_by_key(|(_, e)| e.last_seen).map(|(k, _)| k.clone());
            if let Some(k) = oldest {
                map.remove(&k);
            }
        }
        map.insert(id.clone(), Entry { user, last_seen: now });
        id
    }

    /// Returns the session's user and marks it used, or `None` when the id is
    /// unknown or has been idle too long (it is then removed).
    pub fn touch(&self, id: &str, now: Instant) -> Option<SessionUser> {
        let mut map = self.lock();
        let entry = map.get_mut(id)?;
        if now.duration_since(entry.last_seen) >= IDLE_TIMEOUT {
            map.remove(id);
            return None;
        }
        entry.last_seen = now;
        Some(entry.user.clone())
    }

    /// Ends a session; unknown ids are ignored.
    pub fn remove(&self, id: &str) {
        self.lock().remove(id);
    }

    /// The number of sessions held, live or not yet pruned.
    pub fn len(&self) -> usize {
        self.lock().len()
    }

    /// True when no session is held.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Entry>> {
        // A panic while holding the lock cannot leave the map inconsistent.
        self.inner.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn user(name: &str) -> SessionUser {
        SessionUser { name: name.into(), uid: 1000, admin: false }
    }

    #[test]
    fn ids_are_256_bit_hex_and_unique() {
        let a = new_session_id();
        assert_eq!(a.len(), 64);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, new_session_id());
    }

    #[test]
    fn touch_keeps_a_session_alive_until_idle_timeout() {
        let store = SessionStore::new();
        let t0 = Instant::now();
        let id = store.create(user("kura"), t0);
        let cases = [(Duration::from_secs(60), true), (IDLE_TIMEOUT - Duration::from_secs(1), true)];
        let mut now = t0;
        for (step, alive) in cases {
            now += step;
            assert_eq!(store.touch(&id, now).is_some(), alive);
        }
        assert!(store.touch(&id, now + IDLE_TIMEOUT).is_none());
        assert!(store.is_empty(), "expired session is removed");
        assert!(store.touch("unknown", now).is_none());
    }

    #[test]
    fn remove_ends_a_session() {
        let store = SessionStore::new();
        let now = Instant::now();
        let id = store.create(user("kura"), now);
        store.remove(&id);
        store.remove("unknown");
        assert!(store.touch(&id, now).is_none());
    }

    #[test]
    fn the_store_is_bounded_and_drops_the_oldest() {
        let store = SessionStore::new();
        let t0 = Instant::now();
        let first = store.create(user("first"), t0);
        for i in 1..=MAX_SESSIONS {
            store.create(user("x"), t0 + Duration::from_secs(i as u64));
        }
        assert_eq!(store.len(), MAX_SESSIONS);
        assert!(store.touch(&first, t0 + Duration::from_secs(999)).is_none());
    }

    #[test]
    fn create_prunes_expired_sessions() {
        let store = SessionStore::new();
        let t0 = Instant::now();
        store.create(user("old"), t0);
        store.create(user("new"), t0 + IDLE_TIMEOUT);
        assert_eq!(store.len(), 1);
    }
}
