//! The hottest temperature sensor, from `/sys/class/thermal` and
//! `/sys/class/hwmon` (millidegrees Celsius).

use crate::root::SysRoot;

/// Readings outside this range are sensor noise and ignored.
const PLAUSIBLE: std::ops::RangeInclusive<f64> = -40.0..=150.0;

/// The highest plausible reading in °C, or `None` without sensors.
pub fn read(root: &SysRoot) -> Option<f64> {
    sensor_files(root)
        .into_iter()
        .filter_map(|p| std::fs::read_to_string(p).ok()?.trim().parse::<f64>().ok())
        .map(|milli| milli / 1000.0)
        .filter(|c| PLAUSIBLE.contains(c))
        .reduce(f64::max)
        .map(super::round1)
}

fn sensor_files(root: &SysRoot) -> Vec<std::path::PathBuf> {
    let mut files = Vec::new();
    for (class, prefix, wanted) in [("thermal", "thermal_zone", "temp"), ("hwmon", "hwmon", "_input")] {
        let Ok(dirs) = std::fs::read_dir(root.path(format!("/sys/class/{class}"))) else { continue };
        for dir in dirs.flatten().filter(|d| d.file_name().to_string_lossy().starts_with(prefix)) {
            let Ok(entries) = std::fs::read_dir(dir.path()) else { continue };
            files.extend(entries.flatten().map(|e| e.path()).filter(|p| {
                let name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                name.starts_with("temp") && name.ends_with(wanted)
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
        assert_eq!(read(&f.root()), Some(51.3));
        f.write("sys/class/hwmon/hwmon1/temp1_input", "200000\n");
        f.write("sys/class/hwmon/hwmon1/temp1_label", "60000\n");
        assert_eq!(read(&f.root()), Some(51.3));
    }

    #[test]
    fn none_without_sensors() {
        let f = Fixture::full();
        std::fs::remove_dir_all(f.dir.path().join("sys")).unwrap();
        assert_eq!(read(&f.root()), None);
    }
}
