//! The live [`UnitSource`]: systemd's manager on the system D-Bus, which an
//! unprivileged user may read. Proven by the Linux CI job.

use zbus::OwnedObjectPath;
use zbus::proxy::CacheProperties;

use super::{Unit, UnitSource, UnitsError, UnitsFuture};

/// One row of `ListUnits`: name, description, load, active, sub, following,
/// path, job id, job type, job path.
type RawUnit = (String, String, String, String, String, String, OwnedObjectPath, u32, String, OwnedObjectPath);

#[zbus::proxy(
    interface = "org.freedesktop.systemd1.Manager",
    default_service = "org.freedesktop.systemd1",
    default_path = "/org/freedesktop/systemd1"
)]
trait Manager {
    fn list_units(&self) -> zbus::Result<Vec<RawUnit>>;
}

#[zbus::proxy(interface = "org.freedesktop.systemd1.Unit", default_service = "org.freedesktop.systemd1")]
trait SdUnit {
    #[zbus(property)]
    fn state_change_timestamp(&self) -> zbus::Result<u64>;
}

#[zbus::proxy(interface = "org.freedesktop.systemd1.Service", default_service = "org.freedesktop.systemd1")]
trait SdService {
    #[zbus(property)]
    fn memory_current(&self) -> zbus::Result<u64>;
}

/// Reads services from systemd over a system-bus connection.
pub struct SystemdUnits {
    conn: zbus::Connection,
}

impl SystemdUnits {
    /// Connects to the system bus.
    ///
    /// # Errors
    /// Fails when the system bus is unreachable.
    pub async fn connect() -> Result<Self, UnitsError> {
        let conn = zbus::Connection::system().await.map_err(|e| UnitsError(format!("system bus: {e}")))?;
        Ok(Self { conn })
    }

    async fn read(&self) -> Result<Vec<Unit>, UnitsError> {
        let manager = ManagerProxy::new(&self.conn).await.map_err(err)?;
        let raw = manager.list_units().await.map_err(err)?;
        let mut units = Vec::new();
        for (name, _, load, active, _, _, path, ..) in raw {
            if name.ends_with(".service") && load == "loaded" {
                let (mem, since) = self.details(&path).await;
                units.push(Unit::from_systemd(name, &active, mem, since));
            }
        }
        units.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(units)
    }

    /// `MemoryCurrent` and `StateChangeTimestamp`; either is `None` when
    /// systemd does not answer.
    async fn details(&self, path: &OwnedObjectPath) -> (Option<u64>, Option<u64>) {
        let mem = async {
            let p = SdServiceProxy::builder(&self.conn).path(path.clone());
            p.cache_properties(CacheProperties::No).build().await?.memory_current().await
        };
        let since = async {
            let p = SdUnitProxy::builder(&self.conn).path(path.clone());
            p.cache_properties(CacheProperties::No).build().await?.state_change_timestamp().await
        };
        (mem.await.ok(), since.await.ok())
    }
}

fn err(e: zbus::Error) -> UnitsError {
    UnitsError(e.to_string())
}

impl UnitSource for SystemdUnits {
    fn list(&self) -> UnitsFuture<'_> {
        Box::pin(self.read())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Runs against the host's systemd; the Linux CI job sets
    /// `KURA_LIVE_TESTS=1`.
    #[tokio::test]
    async fn lists_the_live_services() {
        if std::env::var_os("KURA_LIVE_TESTS").is_none() {
            return;
        }
        let units = SystemdUnits::connect().await.unwrap().list().await.unwrap();
        assert!(units.iter().any(|u| u.name == "dbus.service" || u.name == "ssh.service"), "{units:?}");
        assert!(units.windows(2).all(|w| w[0].name <= w[1].name));
    }
}
