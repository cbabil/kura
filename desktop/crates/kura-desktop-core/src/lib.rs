//! Shared pieces of Kura Desktop (ADR-023, ADR-024).
//!
//! Everything here is platform-neutral so `cargo test` runs on macOS:
//! `/proc` and `/sys` are read under a [`root::SysRoot`] that tests point at
//! fixture trees, and systemd sits behind [`units::UnitSource`].

pub mod accounts;
pub mod auth;
pub mod prefs;
pub mod ratelimit;
pub mod root;
pub mod session;
pub mod stats;
pub mod units;
