//! The live [`UnitSource`]: systemd's manager on the system D-Bus, which an
//! unprivileged user may read. Proven by the Linux CI job.

use futures_util::StreamExt;
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

/// systemd answers this many unit lookups at once.
const CONCURRENT: usize = 16;

/// Reads services from systemd over a system-bus connection.
pub struct SystemdUnits {
    conn: zbus::Connection,
    manager: ManagerProxy<'static>,
}

impl SystemdUnits {
    /// Connects to the system bus.
    ///
    /// # Errors
    /// Fails when the system bus is unreachable.
    pub async fn connect() -> Result<Self, UnitsError> {
        let conn = zbus::Connection::system().await.map_err(|e| UnitsError(format!("system bus: {e}")))?;
        let manager = ManagerProxy::new(&conn).await.map_err(err)?;
        Ok(Self { conn, manager })
    }

    async fn read(&self) -> Result<Vec<Unit>, UnitsError> {
        let raw = self.manager.list_units().await.map_err(err)?;
        let services = raw.into_iter().filter(|u| u.0.ends_with(".service") && u.2 == "loaded");
        let mut units: Vec<Unit> = futures_util::stream::iter(services)
            .map(|(name, _, _, active, _, _, path, ..)| async move {
                let (mem, since) = self.details(&path).await;
                Unit::from_systemd(name, &active, mem, since)
            })
            .buffer_unordered(CONCURRENT)
            .collect()
            .await;
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
        let (mem, since) = tokio::join!(mem, since);
        (mem.ok(), since.ok())
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

    /// Runs against the host's systemd.
    #[tokio::test]
    #[ignore = "needs the host's systemd: make test-live"]
    async fn lists_the_live_services() {
        let units = SystemdUnits::connect().await.unwrap().list().await.unwrap();
        assert!(units.iter().any(|u| u.name == "dbus.service" || u.name == "ssh.service"), "{units:?}");
        assert!(units.windows(2).all(|w| w[0].name <= w[1].name));
    }
}
