//! In-memory history: 1 h at one sample per 2 s, and 24 h at one per minute
//! (the average of that minute's samples). Lost when desktopd restarts.

use std::collections::VecDeque;

use super::{Sample, round1};

/// Samples kept for the last hour (`HOUR_POINTS` in types.ts).
pub const HOUR_POINTS: usize = 1800;
/// Minutes kept for the last day (`DAY_POINTS` in types.ts).
pub const DAY_POINTS: usize = 1440;
/// The day ring's step (`DAY_STEP_MS` in types.ts).
pub const DAY_STEP_MS: i64 = 60_000;

/// Both rings and the minute being filled.
#[derive(Debug, Default)]
pub struct History {
    hour: VecDeque<Sample>,
    day: VecDeque<Sample>,
    minute: Vec<Sample>,
}

impl History {
    /// Creates empty rings.
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a sample; closing a minute adds its average to the day ring.
    pub fn push(&mut self, sample: Sample) {
        let bucket = sample.t.div_euclid(DAY_STEP_MS);
        if self.minute.first().is_some_and(|s| s.t.div_euclid(DAY_STEP_MS) != bucket) {
            let avg = average(&self.minute);
            self.minute.clear();
            push_bounded(&mut self.day, avg, DAY_POINTS);
        }
        self.minute.push(sample.clone());
        push_bounded(&mut self.hour, sample, HOUR_POINTS);
    }

    /// The last hour, oldest first.
    pub fn hour(&self) -> &VecDeque<Sample> {
        &self.hour
    }

    /// The last day by minute, oldest first.
    pub fn day(&self) -> &VecDeque<Sample> {
        &self.day
    }
}

fn push_bounded(ring: &mut VecDeque<Sample>, s: Sample, cap: usize) {
    if ring.len() == cap {
        ring.pop_front();
    }
    ring.push_back(s);
}

/// The mean of rates and sizes, the hottest temperature and the latest disks.
fn average(samples: &[Sample]) -> Sample {
    let last = samples.last().cloned().expect("a minute holds at least one sample");
    let n = samples.len() as f64;
    let mean = |f: fn(&Sample) -> f64| samples.iter().map(f).sum::<f64>() / n;
    Sample {
        cpu: round1(mean(|s| s.cpu)),
        mem_used: mean(|s| s.mem_used as f64) as u64,
        mem_cache: mean(|s| s.mem_cache as f64) as u64,
        net_rx: mean(|s| s.net_rx).round(),
        net_tx: mean(|s| s.net_tx).round(),
        temp_c: samples.iter().filter_map(|s| s.temp_c).reduce(f64::max),
        ..last
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(crate) fn sample(t: i64, cpu: f64) -> Sample {
        Sample {
            t,
            cpu,
            mem_used: 100,
            mem_cache: 10,
            mem_total: 1000,
            net_rx: cpu,
            net_tx: 0.0,
            temp_c: None,
            disks: vec![],
        }
    }

    #[test]
    fn hour_ring_is_bounded() {
        let mut h = History::new();
        for i in 0..(HOUR_POINTS as i64 + 5) {
            h.push(sample(i * 2000, 1.0));
        }
        assert_eq!(h.hour().len(), HOUR_POINTS);
        assert_eq!(h.hour().front().unwrap().t, 10_000);
    }

    #[test]
    fn minutes_are_averaged_into_the_day_ring() {
        let mut h = History::new();
        h.push(Sample { temp_c: Some(40.0), ..sample(0, 10.0) });
        h.push(Sample { temp_c: Some(45.0), mem_used: 300, ..sample(30_000, 20.0) });
        assert!(h.day().is_empty(), "minute still open");
        h.push(sample(60_000, 90.0));
        let d = &h.day()[0];
        assert_eq!((d.t, d.cpu, d.mem_used, d.net_rx, d.temp_c), (30_000, 15.0, 200, 15.0, Some(45.0)));
    }

    #[test]
    fn day_ring_is_bounded() {
        let mut h = History::new();
        for m in 0..(DAY_POINTS as i64 + 3) {
            h.push(sample(m * DAY_STEP_MS, 1.0));
        }
        assert_eq!(h.day().len(), DAY_POINTS);
        assert_eq!(h.day().front().unwrap().t, 2 * DAY_STEP_MS);
    }
}
