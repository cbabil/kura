//! The development stand-in for the system behind Settings: one wired and
//! one wireless device, a clock, and changes applied to the development
//! helper's own little root (its `config.json`, `passwd` and `group`), so
//! Settings can be used end to end without touching the machine.

use std::path::PathBuf;
use std::sync::Mutex;

use kura_desktop_core::lock;
use kura_desktop_core::settings::{self, Command};
use kura_helper::Fut;
use kura_helper::system::System;
use serde_json::{Value, json};

/// The first Kura configuration of the development device.
pub const FIRST_CONFIG: &str =
    r#"{"hostname":"kura-dev","networkConfig":{"wifi":{"enable":false},"ethernet":{"enable":true}}}"#;

const DEVICES: &str = "GENERAL.DEVICE:enp1s0\nGENERAL.TYPE:ethernet\nGENERAL.HWADDR:AA\\:BB\\:CC\\:00\\:11\\:22\n\
    GENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:Wired connection 1\nIP4.ADDRESS[1]:192.168.1.50/24\n\
    IP4.GATEWAY:192.168.1.1\nIP4.DNS[1]:192.168.1.1\n\n\
    GENERAL.DEVICE:wlp2s0\nGENERAL.TYPE:wifi\nGENERAL.HWADDR:AA\\:BB\\:CC\\:00\\:11\\:33\n\
    GENERAL.STATE:30 (disconnected)\nGENERAL.CONNECTION:--\nIP4.GATEWAY:--\n";

/// Applies Settings' changes to the files under `root`.
pub struct DevSystem {
    root: PathBuf,
    /// The time zone and whether network time is on.
    clock: Mutex<(String, bool)>,
}

impl DevSystem {
    /// A system whose files are under `root` (which has `etc/`).
    pub fn new(root: PathBuf) -> Self {
        Self { root, clock: Mutex::new(("Europe/Paris".into(), true)) }
    }

    /// A file of the device (`/etc/...`) under the development root.
    fn path(&self, device: &str) -> PathBuf {
        self.root.join(device.trim_start_matches('/'))
    }

    fn edit_config(&self, edit: impl FnOnce(&mut Value)) -> Result<(), String> {
        let path = self.path(settings::CONFIG);
        let text = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
        let mut config: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        edit(&mut config);
        std::fs::write(path, config.to_string()).map_err(|e| e.to_string())
    }

    /// Rewrites `etc/<file>` line by line; `None` drops a line.
    fn edit_lines(&self, file: &str, edit: impl Fn(&str) -> Option<String>, add: Option<String>) -> Result<(), String> {
        let path = self.root.join("etc").join(file);
        let text = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
        let mut lines: Vec<String> = text.lines().filter_map(edit).collect();
        lines.extend(add);
        std::fs::write(path, lines.join("\n") + "\n").map_err(|e| e.to_string())
    }

    /// Adds `name` to the administrators or takes it out.
    fn set_admin(&self, name: &str, admin: bool) -> Result<(), String> {
        self.edit_lines(
            "group",
            |line| {
                let Some(members) = line.strip_prefix("sudo:x:27:") else { return Some(line.to_owned()) };
                let mut names: Vec<&str> = members.split(',').filter(|m| !m.is_empty() && *m != name).collect();
                if admin {
                    names.push(name);
                }
                Some(format!("sudo:x:27:{}", names.join(",")))
            },
            None,
        )
    }

    /// A change to the network part of the configuration.
    fn apply_network(&self, args: &[&str]) -> Result<(), String> {
        let networks = |c: &mut Value, add: Option<Value>| {
            let list = c["networkConfig"]["wifi"]["networks"].as_array().cloned().unwrap_or_default();
            let mut list: Vec<Value> = list.into_iter().filter(|n| n["ssid"] != args[1]).collect();
            list.extend(add);
            c["networkConfig"]["wifi"]["networks"] = Value::Array(list);
        };
        let pending = self.path(settings::PENDING);
        match args[0] {
            "wifi-add" => self.edit_config(|c| networks(c, Some(json!({"ssid": args[1]})))),
            "wifi-remove" => self.edit_config(|c| networks(c, None)),
            "ethernet" => {
                let ipv4 = match args[1] {
                    "static" => json!({"method": "manual", "address": args[2], "gateway": args[3],
                        "dns": args[4].split(',').collect::<Vec<_>>()}),
                    _ => json!({"method": "auto"}),
                };
                std::fs::write(&pending, "{}").map_err(|e| e.to_string())?;
                self.edit_config(|c| c["networkConfig"]["ethernet"]["ipv4"] = ipv4)
            }
            _ => {
                // "network-confirm"; nothing pending is fine too.
                let _ = std::fs::remove_file(&pending);
                Ok(())
            }
        }
    }

    /// A change to the accounts.
    fn apply_user(&self, args: &[&str]) -> Result<(), String> {
        match args[0] {
            "user-add" => {
                let uid = 2000 + std::fs::read_to_string(self.path("/etc/passwd")).map_or(0, |t| t.lines().count());
                let line = format!("{0}:x:{uid}:{uid}::/home/{0}:/bin/sh", args[1]);
                self.edit_lines("passwd", |l| Some(l.to_owned()), Some(line))?;
                self.set_admin(args[1], args[2] == "true")
            }
            "user-remove" => {
                let prefix = format!("{}:", args[1]);
                self.edit_lines("passwd", |l| (!l.starts_with(&prefix)).then(|| l.to_owned()), None)?;
                self.set_admin(args[1], false)
            }
            "user-admin" => self.set_admin(args[1], args[2] == "on"),
            // "user-password": the development accounts keep theirs.
            _ => Ok(()),
        }
    }

    fn apply(&self, command: &[String]) -> Result<(), String> {
        // Padded, so a short command reads "" and never panics.
        let mut args: Vec<&str> = command.iter().map(String::as_str).collect();
        args.resize(args.len().max(5), "");
        match args[0] {
            "hostname" => self.edit_config(|c| c["hostname"] = json!(args[1])),
            "timezone" => {
                lock(&self.clock).0 = args[1].to_owned();
                Ok(())
            }
            "ntp" => {
                lock(&self.clock).1 = args[1] == "on";
                Ok(())
            }
            "screen" => {
                // As systemctl would: the link that turns the unit on.
                let link = self.path("/etc/systemd/system/multi-user.target.wants/kura-kiosk.service");
                match args[1] {
                    "on" => std::fs::create_dir_all(link.parent().unwrap_or(&self.root))
                        .and_then(|()| std::fs::write(&link, ""))
                        .map_err(|e| e.to_string()),
                    _ => {
                        let _ = std::fs::remove_file(&link);
                        Ok(())
                    }
                }
            }
            "wifi-add" | "wifi-remove" | "ethernet" | "network-confirm" => self.apply_network(&args),
            "user-add" | "user-remove" | "user-admin" | "user-password" => self.apply_user(&args),
            other => Err(format!("unknown command {other}")),
        }
    }
}

impl System for DevSystem {
    fn devices(&self) -> Fut<'_, String> {
        Box::pin(async { DEVICES.to_owned() })
    }

    fn clock(&self) -> Fut<'_, String> {
        let (zone, ntp) = lock(&self.clock).clone();
        let yes = |b: bool| if b { "yes" } else { "no" };
        Box::pin(async move { format!("Timezone={zone}\nNTP={}\nNTPSynchronized={}\n", yes(ntp), yes(ntp)) })
    }

    fn change(&self, command: Command) -> Fut<'_, Result<(), String>> {
        let done = self.apply(&command.args);
        Box::pin(async move { done })
    }
}
