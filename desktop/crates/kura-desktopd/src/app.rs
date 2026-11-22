//! Startup: picks the password helper and unit source for this build and
//! platform, starts the sampler, and serves HTTPS (or HTTP in development).

use std::net::{SocketAddr, TcpListener};
use std::sync::Arc;

use axum::Router;
use axum_server::tls_rustls::RustlsConfig;
use kura_desktop_core::root::SysRoot;
use kura_desktop_core::stats::collector::Collector;
use kura_desktop_core::stats::disks::Statvfs;
use kura_desktop_core::stats::sampler::{PERIOD, Sampler, StatsHub};
use kura_desktop_core::units::{StaticUnits, UnitSource};

use crate::config::Config;
use crate::helper::Helper;
use crate::server::{AppState, router};

/// The time a client has to send its request headers.
const HEADER_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
/// HTTP/2 streams per connection.
const MAX_STREAMS: u32 = 32;

/// Why desktopd could not start or stopped.
#[derive(Debug, thiserror::Error)]
pub enum StartError {
    #[error("no password helper: {0}")]
    Helper(String),
    #[error("cannot listen on {0}: {1}")]
    Listen(SocketAddr, std::io::Error),
    #[error("cannot load the TLS certificate {0} or key {1} (made by kura-desktop-cert.service): {2}")]
    Tls(String, String, std::io::Error),
    #[error("server failed: {0}")]
    Serve(std::io::Error),
}

/// Runs desktopd until the listener fails.
///
/// # Errors
/// See [`StartError`].
pub async fn run(config: Config) -> Result<(), StartError> {
    let root = SysRoot::new(&config.root);
    let helper = helper().await?;
    let hub = StatsHub::new();
    let collector = Collector::new(root.clone(), Box::new(Statvfs));
    tokio::spawn(Sampler::new(hub.clone(), collector, units().await).run(PERIOD));
    let mut state = AppState::new(helper, hub, root, &config.state_dir);
    if cfg!(feature = "dev-auth") {
        state.fallback_uid = Some(1000);
    }
    let listener = bind(config.listen)?;
    if config.http {
        state.scheme = "http";
        return serve_http(listener, router(Arc::new(state))).await;
    }
    let (crt, key) = config.tls_files();
    let tls = RustlsConfig::from_pem_file(&crt, &key)
        .await
        .map_err(|e| StartError::Tls(crt.display().to_string(), key.display().to_string(), e))?;
    serve_tls(listener, tls, router(Arc::new(state))).await
}

/// Binds `addr`; on a host without IPv6, `[::]` falls back to `0.0.0.0`.
fn bind(addr: SocketAddr) -> Result<TcpListener, StartError> {
    TcpListener::bind(addr).or_else(|e| {
        let any_v6 = addr.ip() == std::net::Ipv6Addr::UNSPECIFIED;
        if !any_v6 {
            return Err(StartError::Listen(addr, e));
        }
        tracing::warn!("no IPv6 ({e}); listening on IPv4 only");
        let v4 = SocketAddr::from(([0, 0, 0, 0], addr.port()));
        TcpListener::bind(v4).map_err(|e| StartError::Listen(v4, e))
    })
}

/// The fake helper in a dev-auth build.
#[cfg(feature = "dev-auth")]
async fn helper() -> Result<Arc<dyn Helper>, StartError> {
    tracing::warn!("dev-auth build: the development accounts sign in with the development password and get YOUR shell");
    Ok(Arc::new(crate::helper::DevHelper::default()))
}

/// kura-helper on the system bus.
#[cfg(all(not(feature = "dev-auth"), target_os = "linux"))]
async fn helper() -> Result<Arc<dyn Helper>, StartError> {
    let helper = crate::helper::DbusHelper::system().await.map_err(|e| StartError::Helper(e.to_string()))?;
    Ok(Arc::new(helper))
}

#[cfg(all(not(feature = "dev-auth"), not(target_os = "linux")))]
async fn helper() -> Result<Arc<dyn Helper>, StartError> {
    Err(StartError::Helper("kura-helper needs Linux; build with --features dev-auth".into()))
}

/// systemd on Linux; an empty list where there is none.
async fn units() -> Arc<dyn UnitSource> {
    #[cfg(target_os = "linux")]
    match kura_desktop_core::units::systemd::SystemdUnits::connect().await {
        Ok(units) => return Arc::new(units),
        Err(e) => tracing::warn!("services will not be listed: {e}"),
    }
    Arc::new(StaticUnits::default())
}

/// Serves HTTPS on `listener`.
///
/// # Errors
/// [`StartError::Serve`] when the server stops with an error.
pub async fn serve_tls(listener: TcpListener, tls: RustlsConfig, app: Router) -> Result<(), StartError> {
    listener.set_nonblocking(true).map_err(StartError::Serve)?;
    tracing::info!("listening on https://{}", listener.local_addr().map_err(StartError::Serve)?);
    let mut server = axum_server::from_tcp_rustls(listener, tls).map_err(StartError::Serve)?;
    // Slow or idle clients may not hold connections open for long.
    server.http_builder().http1().header_read_timeout(HEADER_TIMEOUT);
    server.http_builder().http2().max_concurrent_streams(MAX_STREAMS).keep_alive_interval(HEADER_TIMEOUT);
    server.serve(app.into_make_service_with_connect_info::<SocketAddr>()).await.map_err(StartError::Serve)
}

/// Serves plain HTTP on `listener` (development only).
///
/// # Errors
/// [`StartError::Serve`] when the server stops with an error.
pub async fn serve_http(listener: TcpListener, app: Router) -> Result<(), StartError> {
    listener.set_nonblocking(true).map_err(StartError::Serve)?;
    let listener = tokio::net::TcpListener::from_std(listener).map_err(StartError::Serve)?;
    tracing::warn!(
        "listening on http://{} without TLS (development)",
        listener.local_addr().map_err(StartError::Serve)?
    );
    let service = app.into_make_service_with_connect_info::<SocketAddr>();
    axum::serve(listener, service).await.map_err(StartError::Serve)
}

/// Makes rustls use the ring provider; call once before serving TLS.
pub fn install_crypto() {
    // An error means a provider is already installed, which is fine.
    let _ = rustls::crypto::ring::default_provider().install_default();
}

#[cfg(test)]
mod tests;
