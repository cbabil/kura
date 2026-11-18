//! systemd services for Activity Monitor. The live source is systemd's
//! `ListUnits` over the system D-Bus (Linux only); tests use [`StaticUnits`].

#[cfg(target_os = "linux")]
pub mod systemd;

use std::future::Future;
use std::pin::Pin;

use serde::Serialize;

/// A unit's state, as `UnitState` in types.ts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum UnitState {
    Active,
    Inactive,
    Failed,
    Activating,
    Deactivating,
}

impl UnitState {
    /// Maps systemd's `ActiveState`; `reloading` and `refreshing` are still
    /// running, and anything unknown reads as inactive.
    pub fn from_systemd(state: &str) -> Self {
        match state {
            "active" | "reloading" | "refreshing" => Self::Active,
            "failed" => Self::Failed,
            "activating" => Self::Activating,
            "deactivating" => Self::Deactivating,
            _ => Self::Inactive,
        }
    }
}

/// A systemd service, as `Unit` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Unit {
    pub name: String,
    pub state: UnitState,
    /// Bytes, or `None` when systemd does not account the unit's memory.
    pub mem: Option<u64>,
    /// Unix ms the unit entered its state, or `None`.
    pub since: Option<i64>,
}

impl Unit {
    /// Builds a unit from systemd's raw values: `MemoryCurrent` is
    /// `u64::MAX` when not accounted, and a timestamp of 0 means never.
    pub fn from_systemd(
        name: String,
        active_state: &str,
        memory_current: Option<u64>,
        since_usec: Option<u64>,
    ) -> Self {
        Self {
            name,
            state: UnitState::from_systemd(active_state),
            mem: memory_current.filter(|m| *m != u64::MAX),
            since: since_usec.filter(|t| *t > 0).map(|t| (t / 1000) as i64),
        }
    }
}

/// The boxed future a [`UnitSource`] returns.
pub type UnitsFuture<'a> = Pin<Box<dyn Future<Output = Result<Vec<Unit>, UnitsError>> + Send + 'a>>;

/// Lists services.
pub trait UnitSource: Send + Sync {
    /// Lists loaded services, sorted by name.
    fn list(&self) -> UnitsFuture<'_>;
}

/// The unit list could not be read.
#[derive(Debug, thiserror::Error)]
#[error("systemd units unavailable: {0}")]
pub struct UnitsError(pub String);

/// A fixed list, for tests and development on a Mac.
#[derive(Debug, Clone, Default)]
pub struct StaticUnits(pub Vec<Unit>);

impl UnitSource for StaticUnits {
    fn list(&self) -> UnitsFuture<'_> {
        let units = self.0.clone();
        Box::pin(async move { Ok(units) })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_systemd_values() {
        let cases = [
            ("active", UnitState::Active),
            ("reloading", UnitState::Active),
            ("failed", UnitState::Failed),
            ("activating", UnitState::Activating),
            ("deactivating", UnitState::Deactivating),
            ("inactive", UnitState::Inactive),
            ("maintenance", UnitState::Inactive),
        ];
        for (raw, want) in cases {
            assert_eq!(UnitState::from_systemd(raw), want, "{raw}");
        }
        let u = Unit::from_systemd("ssh.service".into(), "active", Some(6 << 20), Some(1_700_000_000_123_456));
        assert_eq!((u.mem, u.since), (Some(6 << 20), Some(1_700_000_000_123)));
        let u = Unit::from_systemd("x.service".into(), "inactive", Some(u64::MAX), Some(0));
        assert_eq!((u.mem, u.since), (None, None));
    }

    #[test]
    fn serializes_like_the_interface() {
        let u = Unit::from_systemd("a.service".into(), "failed", None, None);
        let json = serde_json::to_string(&u).unwrap();
        assert_eq!(json, r#"{"name":"a.service","state":"failed","mem":null,"since":null}"#);
    }

    #[tokio::test]
    async fn static_units_list_their_units() {
        let units = vec![Unit::from_systemd("a.service".into(), "active", None, None)];
        assert_eq!(StaticUnits(units.clone()).list().await.unwrap(), units);
        assert!(UnitsError("x".into()).to_string().contains("x"));
    }
}
