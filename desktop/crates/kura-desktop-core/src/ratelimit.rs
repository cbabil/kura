//! Sign-in rate limits: at most 5 failures a minute per source IP and per
//! user name. An attempt counts as a failure while it is in flight, so
//! parallel guesses cannot slip past the limit; a success takes it back.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Failures allowed per key in one [`WINDOW`].
pub const MAX_FAILURES: usize = 5;
/// The sliding window failures are counted over.
pub const WINDOW: Duration = Duration::from_secs(60);
/// Keys tracked at most; past this, the stalest keys are dropped.
const MAX_KEYS: usize = 10_000;

/// Counts failures per key (`ip:…` and `user:…`).
#[derive(Default)]
pub struct RateLimiter {
    inner: Mutex<HashMap<String, VecDeque<Instant>>>,
}

/// An attempt that is counted as a failure unless [`Attempt::succeeded`] is
/// called.
#[derive(Debug)]
pub struct Attempt {
    keys: Vec<String>,
    at: Instant,
}

impl RateLimiter {
    /// Creates an empty limiter.
    pub fn new() -> Self {
        Self::default()
    }

    /// Starts an attempt for `keys`. Refused with the seconds to wait when
    /// any key already has [`MAX_FAILURES`] in the window.
    ///
    /// # Errors
    /// `Err(retry_after_secs)` when the attempt is over the limit.
    pub fn begin(&self, keys: Vec<String>, now: Instant) -> Result<Attempt, u64> {
        let mut map = self.lock();
        let mut wait = Duration::ZERO;
        for key in &keys {
            if let Some(times) = map.get_mut(key) {
                prune(times, now);
                if times.len() >= MAX_FAILURES {
                    wait = wait.max(WINDOW - now.duration_since(times[0]));
                }
            }
        }
        if !wait.is_zero() {
            return Err(wait.as_secs_f64().ceil().max(1.0) as u64);
        }
        if map.len() + keys.len() > MAX_KEYS {
            map.retain(|_, times| {
                prune(times, now);
                !times.is_empty()
            });
            if map.len() + keys.len() > MAX_KEYS {
                // Full of live keys: a flood, so nobody new gets in.
                return Err(WINDOW.as_secs());
            }
        }
        for key in &keys {
            map.entry(key.clone()).or_default().push_back(now);
        }
        Ok(Attempt { keys, at: now })
    }

    /// Takes back an attempt that turned out right.
    pub fn succeeded(&self, attempt: Attempt) {
        let mut map = self.lock();
        for key in &attempt.keys {
            if let Some(times) = map.get_mut(key) {
                if let Some(pos) = times.iter().position(|t| *t == attempt.at) {
                    times.remove(pos);
                }
                if times.is_empty() {
                    map.remove(key);
                }
            }
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, VecDeque<Instant>>> {
        self.inner.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

fn prune(times: &mut VecDeque<Instant>, now: Instant) {
    while times.front().is_some_and(|t| now.duration_since(*t) >= WINDOW) {
        times.pop_front();
    }
}

/// The limiter key for a client address: IPv4 as is, IPv6 by its /64, since
/// one host may use any address of its network.
pub fn ip_key(ip: std::net::IpAddr) -> String {
    match ip.to_canonical() {
        std::net::IpAddr::V4(a) => a.to_string(),
        std::net::IpAddr::V6(a) => {
            let s = a.segments();
            format!("{:x}:{:x}:{:x}:{:x}::/64", s[0], s[1], s[2], s[3])
        }
    }
}

/// The limiter keys for a sign-in from `ip` (an [`ip_key`]) as `user`.
pub fn login_keys(ip: &str, user: &str) -> Vec<String> {
    vec![format!("ip:{ip}"), format!("user:{user}")]
}

#[cfg(test)]
mod tests;
