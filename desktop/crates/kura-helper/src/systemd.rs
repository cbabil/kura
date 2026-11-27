//! systemd's manager on the system bus, as the helper uses it: transient
//! units for the shells of terminals and for jobs. Linux only.

use zbus::{OwnedObjectPath, Variant as Value};

/// How every unit the helper starts for a person begins its description:
/// their names are the apps' own (`terminal-…`, `browser-<user>`), so this is
/// what tells them from another program's unit of the same pattern.
pub const DESCRIBED: &str = "Kura Desktop";

/// True for a unit the helper started, by its description.
pub fn is_ours(description: &str) -> bool {
    description.starts_with(DESCRIBED)
}

/// A unit property: its name and value.
pub type Property<'a> = (&'a str, Value<'a>);

/// One row of `ListUnitsByPatterns`; the first field is the unit's name.
pub type ListedUnit = (String, String, String, String, String, String, OwnedObjectPath, u32, String, OwnedObjectPath);

#[zbus::proxy(
    interface = "org.freedesktop.systemd1.Manager",
    default_service = "org.freedesktop.systemd1",
    default_path = "/org/freedesktop/systemd1"
)]
pub trait Manager {
    fn start_transient_unit(
        &self,
        name: &str,
        mode: &str,
        properties: &[Property<'_>],
        aux: &[(&str, &[Property<'_>])],
    ) -> zbus::Result<OwnedObjectPath>;
    fn start_unit(&self, name: &str, mode: &str) -> zbus::Result<OwnedObjectPath>;
    fn stop_unit(&self, name: &str, mode: &str) -> zbus::Result<OwnedObjectPath>;
    fn reset_failed_unit(&self, name: &str) -> zbus::Result<()>;
    fn list_units_by_patterns(&self, states: &[&str], patterns: &[&str]) -> zbus::Result<Vec<ListedUnit>>;
    fn get_unit(&self, name: &str) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.systemd1.Unit", default_service = "org.freedesktop.systemd1")]
pub trait Unit {
    #[zbus(property)]
    fn active_state(&self) -> zbus::Result<String>;
    #[zbus(property, name = "InvocationID")]
    fn invocation_id(&self) -> zbus::Result<Vec<u8>>;
}

/// The unit called `name`, with properties read afresh each time; `None`
/// when systemd has no such unit (never started, or ended and collected).
pub async fn unit(conn: &zbus::Connection, manager: &ManagerProxy<'_>, name: &str) -> Option<UnitProxy<'static>> {
    let path = manager.get_unit(name).await.ok()?;
    let builder = UnitProxy::builder(conn).path(path);
    builder.cache_properties(zbus::proxy::CacheProperties::No).build().await.ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_units_described_as_kura_desktops_are_its_own() {
        assert!(is_ours("Kura Desktop terminal of anna"));
        assert!(!is_ours("Terminal multiplexer"), "another program's terminal-* unit");
        assert!(!is_ours(""));
    }
}
