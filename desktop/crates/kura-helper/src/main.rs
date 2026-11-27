//! kura-helper: serves `io.kura.Helper` on the system bus as root.

#[cfg(target_os = "linux")]
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    use std::sync::Arc;

    use kura_desktop_core::accounts::Accounts;
    use kura_desktop_core::root::SysRoot;

    /// The user kura-desktopd runs as: the only caller allowed.
    const CALLER: &str = "kura-desktop";
    use kura_helper::docker::EngineDocker;
    use kura_helper::journal::Journalctl;
    use kura_helper::machine::systemd::SystemdMachine;
    use kura_helper::system::systemd::SystemdSystem;
    use kura_helper::terminal::systemd::SystemdShell;
    use kura_helper::{Authenticator, BUS_NAME, Backends, HelperIface, OBJECT_PATH, Service, pam::LinuxPam};

    tracing_subscriber::fmt()
        .with_env_filter("info")
        .without_time()
        .with_ansi(std::io::IsTerminal::is_terminal(&std::io::stdout()))
        .init();
    let Some(caller) = Accounts::load(&SysRoot::default()).by_name(CALLER).map(|a| a.uid) else {
        tracing::error!("no {CALLER} user, so nobody may call {BUS_NAME}");
        return std::process::ExitCode::FAILURE;
    };
    let auth = Arc::new(Authenticator::new(Box::new(LinuxPam), SysRoot::default()));
    // The name is asked for only once the object is served, so no call can
    // arrive before the helper can answer it.
    let conn = async {
        let conn = zbus::Connection::system().await?;
        let backends = Backends {
            docker: Arc::new(EngineDocker::default()),
            journal: Arc::new(Journalctl::default()),
            shells: Arc::new(SystemdShell::new(&conn).await?),
            machine: Arc::new(SystemdMachine::new(&conn).await?),
            system: Arc::new(SystemdSystem::new(&conn).await?),
            apps: Arc::new(kura_helper::apps::systemd::SystemdApps::new(&conn).await?),
            browsers: Arc::new(kura_helper::browser::systemd::SystemdBrowsers::new(&conn).await?),
        };
        // No terminal can be open yet: the tickets of an earlier helper are gone.
        backends.shells.sweep().await;
        let service = Arc::new(Service::new(auth, SysRoot::default(), backends));
        conn.object_server().at(OBJECT_PATH, HelperIface::new(service, Some(caller))).await?;
        conn.request_name(BUS_NAME).await?;
        Ok::<_, zbus::Error>(conn)
    };
    let _conn = match conn.await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("cannot serve {BUS_NAME} on the system bus: {e}");
            return std::process::ExitCode::FAILURE;
        }
    };
    tracing::info!("serving {BUS_NAME}");
    let _ = tokio::signal::ctrl_c().await;
    std::process::ExitCode::SUCCESS
}

#[cfg(not(target_os = "linux"))]
fn main() -> std::process::ExitCode {
    eprintln!("kura-helper runs on Linux only (it needs PAM and the system bus)");
    std::process::ExitCode::FAILURE
}
