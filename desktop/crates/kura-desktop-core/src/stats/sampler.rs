//! The 2-second sampler and the hub that WebSocket clients subscribe to: a
//! snapshot on connect, then one `sample` message per tick to everyone.

use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use tokio::sync::broadcast;

use super::collector::Collector;
use super::history::History;
use super::{Proc, Sample};
use crate::units::{Unit, UnitSource};

/// The sampling period.
pub const PERIOD: Duration = Duration::from_secs(2);
/// Units are listed every this many ticks (10 s), since that is costlier.
const UNITS_EVERY: u64 = 5;
/// Ticks between re-reads of user names, sensors and mounts (1 min).
const REFRESH_EVERY: u64 = 30;

#[derive(Serialize)]
struct Ranges<'a> {
    #[serde(rename = "1h")]
    hour: &'a std::collections::VecDeque<Sample>,
    #[serde(rename = "24h")]
    day: &'a std::collections::VecDeque<Sample>,
}

/// `StatsMessage` in types.ts.
#[derive(Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
enum Message<'a> {
    Snapshot {
        history: Ranges<'a>,
        units: &'a [Unit],
        procs: &'a [Proc],
    },
    Sample {
        sample: &'a Sample,
        #[serde(skip_serializing_if = "Option::is_none")]
        units: Option<&'a [Unit]>,
        procs: &'a [Proc],
    },
}

#[derive(Default)]
struct State {
    history: History,
    units: Vec<Unit>,
    procs: Vec<Proc>,
}

/// Holds history and fans samples out to subscribers as JSON text.
pub struct StatsHub {
    state: Mutex<State>,
    tx: broadcast::Sender<Arc<str>>,
}

impl Default for StatsHub {
    fn default() -> Self {
        Self { state: Mutex::default(), tx: broadcast::channel(16).0 }
    }
}

impl StatsHub {
    /// Creates an empty hub.
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// The snapshot message and a receiver for every later sample, taken
    /// together so none is missed or repeated.
    pub fn subscribe(&self) -> (String, broadcast::Receiver<Arc<str>>) {
        let state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        let history = Ranges { hour: state.history.hour(), day: state.history.day() };
        let msg = Message::Snapshot { history, units: &state.units, procs: &state.procs };
        (to_json(&msg), self.tx.subscribe())
    }

    /// Records a sample and sends it; `units` is `Some` when freshly listed.
    pub fn record(&self, sample: Sample, procs: Vec<Proc>, units: Option<Vec<Unit>>) {
        let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        let fresh = units.is_some();
        if let Some(units) = units {
            state.units = units;
        }
        state.procs = procs;
        let units = fresh.then_some(state.units.as_slice());
        let text: Arc<str> = to_json(&Message::Sample { sample: &sample, units, procs: &state.procs }).into();
        state.history.push(sample);
        // No receiver is not an error: nobody has Activity Monitor open.
        let _ = self.tx.send(text);
    }
}

fn to_json(msg: &Message<'_>) -> String {
    serde_json::to_string(msg).expect("stats messages always serialize")
}

/// Drives a [`Collector`] and a [`UnitSource`] into a [`StatsHub`].
pub struct Sampler {
    hub: Arc<StatsHub>,
    collector: Arc<Mutex<Collector>>,
    units: Arc<dyn UnitSource>,
    tick: u64,
}

impl Sampler {
    /// A sampler feeding `hub`.
    pub fn new(hub: Arc<StatsHub>, collector: Collector, units: Arc<dyn UnitSource>) -> Self {
        Self { hub, collector: Arc::new(Mutex::new(collector)), units, tick: 0 }
    }

    /// Takes one sample; file reads run on the blocking pool while units
    /// are listed.
    pub async fn step(&mut self) {
        let refresh = self.tick > 0 && self.tick.is_multiple_of(REFRESH_EVERY);
        let t = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64);
        let collector = self.collector.clone();
        let read = tokio::task::spawn_blocking(move || {
            let mut c = collector.lock().unwrap_or_else(PoisonError::into_inner);
            if refresh {
                c.refresh();
            }
            c.collect(t, Instant::now())
        });
        let list = async { if self.tick.is_multiple_of(UNITS_EVERY) { self.list_units().await } else { None } };
        let (read, units) = tokio::join!(read, list);
        self.tick += 1;
        match read {
            Ok(Ok((sample, procs))) => self.hub.record(sample, procs, units),
            Ok(Err(e)) => tracing::warn!("stats sample skipped: {e}"),
            Err(e) => tracing::error!("stats collector failed: {e}"),
        }
    }

    async fn list_units(&self) -> Option<Vec<Unit>> {
        self.units.list().await.inspect_err(|e| tracing::warn!("{e}")).ok()
    }

    /// Samples every `period` until the task is dropped.
    pub async fn run(mut self, period: Duration) {
        let mut timer = tokio::time::interval(period);
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            timer.tick().await;
            self.step().await;
        }
    }
}

#[cfg(test)]
mod tests;
