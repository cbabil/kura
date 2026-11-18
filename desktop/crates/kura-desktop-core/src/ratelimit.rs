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
    pub fn begin(&self, keys: &[String], now: Instant) -> Result<Attempt, u64> {
        let mut map = self.lock();
        let mut wait = Duration::ZERO;
        for key in keys {
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
        }
        for key in keys {
            map.entry(key.clone()).or_default().push_back(now);
        }
        Ok(Attempt { keys: keys.to_vec(), at: now })
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

/// The limiter keys for a sign-in from `ip` as `user`.
pub fn login_keys(ip: &str, user: &str) -> Vec<String> {
    vec![format!("ip:{ip}"), format!("user:{user}")]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn five_failures_then_refused_until_the_window_passes() {
        let rl = RateLimiter::new();
        let t0 = Instant::now();
        let keys = login_keys("10.0.0.2", "kura");
        for i in 0..MAX_FAILURES {
            assert!(rl.begin(&keys, t0 + Duration::from_secs(i as u64)).is_ok());
        }
        assert_eq!(rl.begin(&keys, t0 + Duration::from_secs(10)).unwrap_err(), 50);
        assert!(rl.begin(&keys, t0 + WINDOW).is_ok(), "oldest failure aged out");
    }

    #[test]
    fn per_ip_and_per_user_limits_are_independent() {
        let rl = RateLimiter::new();
        let now = Instant::now();
        for i in 0..MAX_FAILURES {
            rl.begin(&login_keys("10.0.0.2", &format!("u{i}")), now).unwrap();
        }
        assert!(rl.begin(&login_keys("10.0.0.2", "other"), now).is_err(), "same IP");
        assert!(rl.begin(&login_keys("10.0.0.3", "other"), now).is_ok(), "other IP");
        for i in 0..MAX_FAILURES {
            rl.begin(&login_keys(&format!("10.1.0.{i}"), "anna"), now).unwrap();
        }
        assert!(rl.begin(&login_keys("10.9.9.9", "anna"), now).is_err(), "same user");
    }

    #[test]
    fn a_success_does_not_count() {
        let rl = RateLimiter::new();
        let now = Instant::now();
        let keys = login_keys("10.0.0.2", "kura");
        for _ in 0..MAX_FAILURES * 2 {
            let attempt = rl.begin(&keys, now).unwrap();
            rl.succeeded(attempt);
        }
        assert!(rl.lock().is_empty());
        let a = rl.begin(&keys, now).unwrap();
        rl.begin(&keys, now).unwrap();
        rl.succeeded(a);
        assert_eq!(rl.lock()[&keys[0]].len(), 1);
    }

    #[test]
    fn retry_after_is_at_least_one_second() {
        let rl = RateLimiter::new();
        let t0 = Instant::now();
        let keys = login_keys("ip", "u");
        for _ in 0..MAX_FAILURES {
            rl.begin(&keys, t0).unwrap();
        }
        let wait = rl.begin(&keys, t0 + WINDOW - Duration::from_millis(1)).unwrap_err();
        assert_eq!(wait, 1);
    }

    #[test]
    fn stale_keys_are_dropped_past_the_cap() {
        let rl = RateLimiter::new();
        let t0 = Instant::now();
        for i in 0..MAX_KEYS / 2 {
            rl.begin(&login_keys(&i.to_string(), &i.to_string()), t0).unwrap();
        }
        rl.begin(&login_keys("new", "new"), t0 + WINDOW).unwrap();
        assert_eq!(rl.lock().len(), 2);
    }
}
