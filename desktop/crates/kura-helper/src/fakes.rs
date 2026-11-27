//! Stand-ins for Docker, the journal and systemd, for this crate's tests and
//! desktopd's (the `fakes` feature).

mod system;

pub use system::{FakeApps, FakeMachine, FakeSystem};

use crate::browser::Browsers;

use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

use kura_desktop_core::accounts::Account;
use kura_desktop_core::containers::{Container, ContainerAction, LogLine, parse_list};
use kura_desktop_core::journal::{JournalPage, JournalQuery, parse_page};

use crate::Fut;
use crate::docker::{Docker, DockerError};
use crate::journal::{Journal, JournalError};
use crate::terminal::ShellLauncher;

/// The id of the one container [`FakeDocker`] has.
pub const CONTAINER: &str = "aaaaaaaaaaaa";

/// One running container; `down` makes Docker unreachable.
#[derive(Default)]
pub struct FakeDocker {
    pub down: AtomicBool,
    /// "start aaaaaaaaaaaa", ...
    pub calls: Mutex<Vec<String>>,
}

impl FakeDocker {
    fn up(&self) -> Result<(), DockerError> {
        if self.down.load(Ordering::Relaxed) { Err(DockerError::Unavailable("down".into())) } else { Ok(()) }
    }
}

impl Docker for FakeDocker {
    fn list(&self) -> Fut<'_, Result<Vec<Container>, DockerError>> {
        let json =
            format!(r#"[{{"Id":"{CONTAINER}","Names":["/web"],"Image":"nginx","State":"running","Created":1}}]"#);
        Box::pin(async move { self.up().map(|()| parse_list(json.as_bytes()).unwrap_or_default()) })
    }

    fn act<'a>(&'a self, id: &'a str, action: ContainerAction) -> Fut<'a, Result<(), DockerError>> {
        Box::pin(async move {
            self.up()?;
            if id != CONTAINER {
                return Err(DockerError::NotFound);
            }
            self.calls.lock().unwrap().push(format!("{} {id}", action.as_str()));
            Ok(())
        })
    }

    fn logs<'a>(&'a self, id: &'a str, lines: u32) -> Fut<'a, Result<Vec<LogLine>, DockerError>> {
        Box::pin(async move {
            self.up()?;
            if id != CONTAINER {
                return Err(DockerError::NotFound);
            }
            Ok(vec![LogLine { t: Some(1), stream: "stdout", text: format!("last {lines}") }])
        })
    }
}

/// A journal of one entry that echoes journalctl's arguments.
#[derive(Default)]
pub struct FakeJournal {
    pub down: AtomicBool,
}

impl Journal for FakeJournal {
    fn read<'a>(&'a self, query: &'a JournalQuery) -> Fut<'a, Result<JournalPage, JournalError>> {
        Box::pin(async move {
            if self.down.load(Ordering::Relaxed) {
                return Err(JournalError("down".into()));
            }
            let line = serde_json::json!({"__CURSOR": "s=1", "__REALTIME_TIMESTAMP": "1000",
                "MESSAGE": query.to_args().join(" ")});
            Ok(parse_page(line.to_string().as_bytes()))
        })
    }
}

/// "Shells" that are one end of a socket pair: what is written to the
/// master comes back in upper case, like a very small terminal.
#[derive(Default)]
pub struct FakeShell {
    pub fail: AtomicBool,
    /// Set to make every shell look ended.
    pub ended: AtomicBool,
    pub opened: Mutex<Vec<String>>,
    pub closed: Mutex<Vec<String>>,
    /// A second handle on every end given out. On macOS a socket that is
    /// closed by its sender while it crosses the bus can arrive already
    /// ended; held here, it is never closed in flight.
    held: Mutex<Vec<UnixStream>>,
}

impl ShellLauncher for FakeShell {
    fn open<'a>(&'a self, account: &'a Account, cols: u16, rows: u16) -> Fut<'a, Result<(OwnedFd, String), String>> {
        Box::pin(async move {
            if self.fail.load(Ordering::Relaxed) {
                return Err("systemd said no".into());
            }
            // Lets a test act while the shell is "starting".
            tokio::task::yield_now().await;
            let (master, shell) = UnixStream::pair().map_err(|e| e.to_string())?;
            self.held.lock().unwrap().extend(master.try_clone());
            std::thread::spawn(move || echo_upper(shell));
            let mut opened = self.opened.lock().unwrap();
            let handle = format!("{}-{cols}x{rows}-{}", account.name, opened.len());
            opened.push(handle.clone());
            Ok((master.into(), handle))
        })
    }

    fn open_agent<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<(OwnedFd, String), String>> {
        Box::pin(async move {
            if self.fail.load(Ordering::Relaxed) {
                return Err("systemd said no".into());
            }
            let (ours, theirs) = UnixStream::pair().map_err(|e| e.to_string())?;
            self.held.lock().unwrap().extend(ours.try_clone());
            std::thread::spawn(move || echo_upper(theirs));
            let mut opened = self.opened.lock().unwrap();
            let handle = format!("{}-files-{}", account.name, opened.len());
            opened.push(handle.clone());
            Ok((ours.into(), handle))
        })
    }

    fn running<'a>(&'a self, _handle: &'a str) -> Fut<'a, bool> {
        Box::pin(async { !self.ended.load(Ordering::Relaxed) })
    }

    fn close<'a>(&'a self, handle: &'a str) -> Fut<'a, ()> {
        Box::pin(async move { self.closed.lock().unwrap().push(handle.to_owned()) })
    }

    fn sweep(&self) -> Fut<'_, ()> {
        Box::pin(async { self.closed.lock().unwrap().push("swept".into()) })
    }
}

fn echo_upper(mut shell: UnixStream) {
    use std::io::{ErrorKind, Read, Write};
    let mut buf = [0u8; 256];
    loop {
        match shell.read(&mut buf) {
            // A signal meant for another thread (a child of some other test ending) is not the end.
            Err(e) if e.kind() == ErrorKind::Interrupted => {}
            Ok(n @ 1..) if shell.write_all(&buf[..n].to_ascii_uppercase()).is_ok() => {}
            _ => break,
        }
    }
}

/// Browsers that record what they were asked: an open hands over one end of
/// a socket pair and keeps the other (the "server") in `servers`.
#[derive(Default)]
pub struct FakeBrowsers {
    pub fail: AtomicBool,
    /// "open anna", "stop anna", ...
    pub calls: Mutex<Vec<String>>,
    pub servers: Mutex<Vec<UnixStream>>,
}

impl Browsers for FakeBrowsers {
    fn open<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<OwnedFd, String>> {
        let opened = if self.fail.load(Ordering::Relaxed) {
            Err("systemd said no".to_owned())
        } else {
            self.calls.lock().unwrap().push(format!("open {}", account.name));
            UnixStream::pair().map_err(|e| e.to_string()).map(|(ours, server)| {
                self.servers.lock().unwrap().push(server);
                ours.into()
            })
        };
        Box::pin(async move { opened })
    }

    fn stop<'a>(&'a self, user: &'a str) -> Fut<'a, ()> {
        self.calls.lock().unwrap().push(format!("stop {user}"));
        Box::pin(async {})
    }
}
