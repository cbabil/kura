//! Stand-ins for the machine (power, updates) and the system behind
//! Settings.

use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use kura_desktop_core::actions::{PowerKind, UpdateKind};
use kura_desktop_core::settings::Command;
use kura_desktop_core::updates::JobState;

use crate::Fut;
use crate::apps::Apps;
use crate::machine::Machine;
use crate::system::System;

/// A machine that records what it was asked: Kura 0.6.1 installed, 0.6.2
/// waiting, and an update job that is "running" once started.
#[derive(Default)]
pub struct FakeMachine {
    pub fail: AtomicBool,
    /// "restart", "shutdown", "check", "install", "browser on", "browser off".
    pub asked: Mutex<Vec<&'static str>>,
    /// How often the job's output was read.
    pub outputs: AtomicUsize,
}

impl FakeMachine {
    fn ask(&self, what: &'static str) -> Result<(), String> {
        if self.fail.load(Ordering::Relaxed) {
            return Err("systemd said no".into());
        }
        self.asked.lock().unwrap().push(what);
        Ok(())
    }
}

impl Machine for FakeMachine {
    fn power(&self, how: PowerKind) -> Fut<'_, Result<(), String>> {
        let done = self.ask(if how == PowerKind::Restart { "restart" } else { "shutdown" });
        Box::pin(async move { done })
    }

    fn apt_policy(&self) -> Fut<'_, String> {
        Box::pin(async { "kura:\n  Installed: 0.6.1\n  Candidate: 0.6.2\n".to_owned() })
    }

    fn start_update(&self, what: UpdateKind) -> Fut<'_, Result<(), String>> {
        let done = self.ask(if what == UpdateKind::Check { "check" } else { "install" });
        Box::pin(async move { done })
    }

    fn job_state(&self) -> Fut<'_, Option<JobState>> {
        let started = self.asked.lock().unwrap().iter().any(|a| matches!(*a, "check" | "install"));
        Box::pin(async move { started.then_some(JobState::Running) })
    }

    fn job_output(&self) -> Fut<'_, Vec<String>> {
        self.outputs.fetch_add(1, Ordering::Relaxed);
        Box::pin(async { vec!["Get:1 kura 0.6.2".into()] })
    }

    fn browser(&self, on: bool) -> Fut<'_, Result<(), String>> {
        let done = self.ask(if on { "browser on" } else { "browser off" });
        Box::pin(async move { done })
    }
}

/// A system with one Ethernet device and a clock in Paris; it records the
/// commands it was asked to run (and their secrets) and can refuse them.
#[derive(Default)]
pub struct FakeSystem {
    pub refuse: Mutex<Option<String>>,
    /// The argument lists, joined by spaces.
    pub commands: Mutex<Vec<String>>,
    pub secrets: Mutex<Vec<String>>,
    running: AtomicUsize,
    /// The most commands that ever ran at the same time.
    pub most_at_once: AtomicUsize,
}

impl System for FakeSystem {
    fn devices(&self) -> Fut<'_, String> {
        Box::pin(async {
            "GENERAL.DEVICE:enp1s0\nGENERAL.TYPE:ethernet\nGENERAL.STATE:100 (connected)\nIP4.ADDRESS[1]:192.168.1.50/24\n".to_owned()
        })
    }

    fn clock(&self) -> Fut<'_, String> {
        Box::pin(async { "Timezone=Europe/Paris\nNTP=yes\nNTPSynchronized=yes\n".to_owned() })
    }

    fn change(&self, command: Command) -> Fut<'_, Result<(), String>> {
        if let Some(why) = self.refuse.lock().unwrap().clone() {
            return Box::pin(async move { Err(why) });
        }
        self.commands.lock().unwrap().push(command.args.join(" "));
        self.secrets.lock().unwrap().extend(command.secret.iter().map(|s| s.to_string()));
        Box::pin(async {
            let now = self.running.fetch_add(1, Ordering::SeqCst) + 1;
            self.most_at_once.fetch_max(now, Ordering::SeqCst);
            tokio::task::yield_now().await;
            self.running.fetch_sub(1, Ordering::SeqCst);
            Ok(())
        })
    }
}

/// Catalog jobs that record their arguments; the last one "runs" until
/// `finish` is set.
#[derive(Default)]
pub struct FakeApps {
    pub fail: AtomicBool,
    pub finish: AtomicBool,
    /// The argument lists, joined by spaces.
    pub started: Mutex<Vec<String>>,
}

impl Apps for FakeApps {
    fn start(&self, args: Vec<String>) -> Fut<'_, Result<(), String>> {
        let done = if self.fail.load(Ordering::Relaxed) {
            Err("systemd said no".to_owned())
        } else {
            self.started.lock().unwrap().push(args.join(" "));
            Ok(())
        };
        Box::pin(async move { done })
    }

    fn job_state(&self) -> Fut<'_, Option<JobState>> {
        let started = !self.started.lock().unwrap().is_empty();
        let state = if self.finish.load(Ordering::Relaxed) { JobState::Done } else { JobState::Running };
        Box::pin(async move { started.then_some(state) })
    }

    fn job_output(&self) -> Fut<'_, Vec<String>> {
        Box::pin(async { vec!["Pulling jellyfin".into()] })
    }
}
