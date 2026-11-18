//! kura-helper: serves `io.kura.Helper` on the system bus as root.

#[cfg(target_os = "linux")]
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    use std::sync::Arc;

    use kura_desktop_core::root::SysRoot;
    use kura_helper::{Authenticator, BUS_NAME, HelperIface, OBJECT_PATH, pam::LinuxPam};

    tracing_subscriber::fmt()
        .with_env_filter("info")
        .without_time()
        .with_ansi(std::io::IsTerminal::is_terminal(&std::io::stdout()))
        .init();
    let auth = Arc::new(Authenticator::new(Box::new(LinuxPam::login()), SysRoot::default()));
    let conn = async {
        zbus::connection::Builder::system().name(BUS_NAME).serve_at(OBJECT_PATH, HelperIface::new(auth)).build().await
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
