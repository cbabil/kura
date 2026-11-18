//! The hottest temperature sensor, from `/sys/class/thermal` and
//! `/sys/class/hwmon` (millidegrees Celsius).

use std::path::PathBuf;

use crate::root::SysRoot;

/// Readings outside this range are sensor noise and ignored.
const PLAUSIBLE: std::ops::RangeInclusive<f64> = -40.0..=150.0;

/// The highest plausible reading in °C among `sensors`, or `None`.
pub fn read(sensors: &[PathBuf]) -> Option<f64> {
    sensors
        .iter()
        .filter_map(|p| std::fs::read_to_string(p).ok()?.trim().parse::<f64>().ok())
        .map(|milli| milli / 1000.0)
        .filter(|c| PLAUSIBLE.contains(c))
        .reduce(f64::max)
        .map(super::round1)
}

/// Finds the sensor files once; they do not come and go at runtime.
pub fn sensors(root: &SysRoot) -> Vec<PathBuf> {
    let mut files = Vec::new();
    for (class, prefix, wanted) in [("thermal", "thermal_zone", "temp"), ("hwmon", "hwmon", "_input")] {
        let Ok(dirs) = std::fs::read_dir(root.path(format!("/sys/class/{class}"))) else { continue };
        for dir in dirs.flatten().filter(|d| d.file_name().to_str().is_some_and(|n| n.starts_with(prefix))) {
            let Ok(entries) = std::fs::read_dir(dir.path()) else { continue };
            files.extend(entries.flatten().map(|e| e.path()).filter(|p| {
                p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("temp") && n.ends_with(wanted))
            }));
        }
    }
    files
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stats::fixture::Fixture;

    #[test]
    fn takes_the_hottest_plausible_sensor() {
        let f = Fixture::full();
        assert_eq!(read(&sensors(&f.root())), Some(51.3));
        f.write("sys/class/hwmon/hwmon1/temp1_input", "200000\n");
        f.write("sys/class/hwmon/hwmon1/temp1_label", "60000\n");
        assert_eq!(read(&sensors(&f.root())), Some(51.3));
    }

    #[test]
    fn none_without_sensors() {
        let f = Fixture::full();
        std::fs::remove_dir_all(f.dir.path().join("sys")).unwrap();
        assert_eq!(read(&sensors(&f.root())), None);
    }
}
