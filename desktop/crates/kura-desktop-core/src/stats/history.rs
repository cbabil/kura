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

/// Running sums of the minute being filled.
#[derive(Debug, Default)]
struct Minute {
    bucket: i64,
    n: u32,
    cpu: f64,
    mem_used: f64,
    mem_cache: f64,
    net_rx: f64,
    net_tx: f64,
    temp_c: Option<f64>,
}

impl Minute {
    fn add(&mut self, s: &Sample) {
        self.n += 1;
        self.cpu += s.cpu;
        self.mem_used += s.mem_used as f64;
        self.mem_cache += s.mem_cache as f64;
        self.net_rx += s.net_rx;
        self.net_tx += s.net_tx;
        self.temp_c = self.temp_c.into_iter().chain(s.temp_c).reduce(f64::max);
    }

    /// The minute's means and hottest temperature, on top of its last sample
    /// (which gives the time, memory total and disks).
    fn average(&self, last: &Sample) -> Sample {
        let n = f64::from(self.n);
        Sample {
            cpu: round1(self.cpu / n),
            mem_used: (self.mem_used / n) as u64,
            mem_cache: (self.mem_cache / n) as u64,
            net_rx: (self.net_rx / n).round(),
            net_tx: (self.net_tx / n).round(),
            temp_c: self.temp_c,
            ..last.clone()
        }
    }
}

/// Both rings and the minute being filled.
#[derive(Debug, Default)]
pub struct History {
    hour: VecDeque<Sample>,
    day: VecDeque<Sample>,
    minute: Minute,
}

impl History {
    /// Creates empty rings.
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a sample; closing a minute adds its average to the day ring.
    pub fn push(&mut self, sample: Sample) {
        let bucket = sample.t.div_euclid(DAY_STEP_MS);
        if self.minute.n > 0 && self.minute.bucket != bucket {
            if let Some(last) = self.hour.back() {
                let avg = self.minute.average(last);
                push_bounded(&mut self.day, avg, DAY_POINTS);
            }
            self.minute = Minute::default();
        }
        self.minute.bucket = bucket;
        self.minute.add(&sample);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(t: i64, cpu: f64) -> Sample {
        Sample { t, cpu, mem_used: 100, mem_cache: 10, mem_total: 1000, net_rx: cpu, ..Sample::default() }
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
