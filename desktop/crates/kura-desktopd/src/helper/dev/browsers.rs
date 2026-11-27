//! The development Browser: no Chromium, only a stand-in VNC server that
//! greets as RFB does and then echoes, one for each person, so the relay can
//! be driven end to end. A stop hangs up on everyone viewing that person's.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::sync::Mutex;

use kura_desktop_core::accounts::Account;
use kura_desktop_core::lock;
use kura_helper::Fut;
use kura_helper::browser::Browsers;

/// Each person's open connections, to hang up on at a stop.
#[derive(Default)]
pub struct DevBrowsers {
    open: Mutex<HashMap<String, Vec<UnixStream>>>,
}

/// Greets, then sends back whatever comes, until either side hangs up.
fn serve(mut stream: UnixStream) {
    if stream.write_all(b"RFB 003.008\n").is_err() {
        return;
    }
    let mut buf = [0u8; 4096];
    while let Ok(n @ 1..) = stream.read(&mut buf) {
        if stream.write_all(&buf[..n]).is_err() {
            return;
        }
    }
}

impl Browsers for DevBrowsers {
    fn open<'a>(&'a self, account: &'a Account) -> Fut<'a, Result<OwnedFd, String>> {
        let opened = UnixStream::pair().and_then(|(ours, server)| {
            let kept = server.try_clone()?;
            std::thread::spawn(move || serve(server));
            lock(&self.open).entry(account.name.clone()).or_default().push(kept);
            Ok(ours.into())
        });
        Box::pin(async move { opened.map_err(|e| e.to_string()) })
    }

    fn stop<'a>(&'a self, user: &'a str) -> Fut<'a, ()> {
        for stream in lock(&self.open).remove(user).unwrap_or_default() {
            let _ = stream.shutdown(std::net::Shutdown::Both);
        }
        Box::pin(async {})
    }
}
