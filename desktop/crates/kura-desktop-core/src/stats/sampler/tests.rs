use super::*;
use crate::stats::fixture::{FakeFs, Fixture};
use crate::units::{StaticUnits, UnitsError, UnitsFuture};

struct Broken;
impl UnitSource for Broken {
    fn list(&self) -> UnitsFuture<'_> {
        Box::pin(async { Err(UnitsError("no bus".into())) })
    }
}

fn units() -> Arc<dyn UnitSource> {
    Arc::new(StaticUnits(vec![Unit::from_systemd("ssh.service".into(), "active", Some(1), None)]))
}

fn json(text: &str) -> serde_json::Value {
    serde_json::from_str(text).unwrap()
}

#[tokio::test]
async fn snapshot_then_samples_with_units_every_fifth_tick() {
    let f = Fixture::full();
    let hub = StatsHub::new();
    let (snap, mut rx) = hub.subscribe();
    let snap = json(&snap);
    assert_eq!(snap["type"], "snapshot");
    assert_eq!(snap["history"]["1h"].as_array().unwrap().len(), 0);
    assert!(snap["history"]["24h"].is_array());

    let mut sampler = Sampler::new(hub.clone(), Collector::new(f.root(), Box::new(FakeFs)), units());
    for _ in 0..6 {
        sampler.step().await;
    }
    let msgs: Vec<serde_json::Value> = (0..6).map(|_| json(&rx.try_recv().unwrap())).collect();
    assert!(msgs.iter().all(|m| m["type"] == "sample" && m["procs"].is_array()));
    let with_units: Vec<bool> = msgs.iter().map(|m| m.get("units").is_some()).collect();
    assert_eq!(with_units, [true, false, false, false, false, true]);
    assert_eq!(msgs[0]["units"][0]["name"], "ssh.service");
    assert!(msgs[0]["sample"]["memTotal"].as_u64().unwrap() > 0);
    assert!(msgs[0]["sample"].get("tempC").is_some());

    let (snap, _) = hub.subscribe();
    let snap = json(&snap);
    assert_eq!(snap["history"]["1h"].as_array().unwrap().len(), 6);
    assert_eq!(snap["units"][0]["state"], "active");
}

#[tokio::test]
async fn failures_skip_samples_without_stopping() {
    let f = Fixture::full();
    let hub = StatsHub::new();
    let (_, mut rx) = hub.subscribe();
    let mut sampler = Sampler::new(hub.clone(), Collector::new(f.root(), Box::new(FakeFs)), Arc::new(Broken));
    sampler.tick = REFRESH_EVERY;
    sampler.step().await;
    assert!(json(&rx.try_recv().unwrap()).get("units").is_none());
    std::fs::remove_file(f.dir.path().join("proc/stat")).unwrap();
    sampler.step().await;
    assert!(rx.try_recv().is_err(), "a failed sample is not sent");
}

#[tokio::test]
async fn run_samples_on_a_timer() {
    let f = Fixture::full();
    let hub = StatsHub::new();
    let (_, mut rx) = hub.subscribe();
    let task = tokio::spawn(
        Sampler::new(hub, Collector::new(f.root(), Box::new(FakeFs)), units()).run(Duration::from_millis(10)),
    );
    for _ in 0..2 {
        let msg = tokio::time::timeout(Duration::from_secs(5), rx.recv()).await.unwrap().unwrap();
        assert_eq!(json(&msg)["type"], "sample");
    }
    task.abort();
}

#[test]
fn record_without_subscribers_is_fine() {
    let hub = StatsHub::new();
    hub.record(Sample::default(), vec![], None);
    assert_eq!(json(&hub.subscribe().0)["history"]["1h"].as_array().unwrap().len(), 1);
}
