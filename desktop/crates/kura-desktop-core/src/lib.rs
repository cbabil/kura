//! Shared pieces of Kura Desktop (ADR-023, ADR-024).
//!
//! Everything here is platform-neutral so `cargo test` runs on macOS:
//! `/proc` and `/sys` are read under a [`root::SysRoot`] that tests point at
//! fixture trees, and systemd sits behind [`units::UnitSource`].

pub mod accounts;
pub mod actions;
pub mod auth;
pub mod browser;
pub mod catalog;
pub mod containers;
pub mod files;
pub mod journal;
pub mod prefs;
pub mod ratelimit;
pub mod refusal;
pub mod root;
pub mod session;
pub mod settings;
pub mod stats;
pub mod terminal;
pub mod units;
pub mod updates;

/// Locks `mutex` whether or not a thread panicked while holding it: the
/// values kept this way stay consistent step by step, so nothing is lost.
pub fn lock<T>(mutex: &std::sync::Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}
