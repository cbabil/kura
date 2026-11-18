use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};

use super::*;
use crate::helper::DevHelper;

fn app() -> (Router, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let state = AppState::new(Arc::new(DevHelper), StatsHub::new(), SysRoot::new(dir.path()), dir.path());
    (router(Arc::new(state)), dir)
}

async fn get(stream: &mut (impl AsyncReadExt + AsyncWriteExt + Unpin)) -> String {
    stream.write_all(b"GET /api/session HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").await.unwrap();
    let mut out = Vec::new();
    tokio::time::timeout(Duration::from_secs(5), stream.read_to_end(&mut out)).await.unwrap().unwrap();
    String::from_utf8_lossy(&out).into_owned()
}

#[tokio::test]
async fn serves_https_with_the_given_certificate() {
    install_crypto();
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let tls = RustlsConfig::from_pem(cert.cert.pem().into_bytes(), cert.signing_key.serialize_pem().into_bytes())
        .await
        .unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let (router, _dir) = app();
    tokio::spawn(serve_tls(listener, tls, router));

    let mut roots = rustls::RootCertStore::empty();
    roots.add(cert.cert.der().clone()).unwrap();
    let client = rustls::ClientConfig::builder().with_root_certificates(roots).with_no_client_auth();
    let connector = tokio_rustls::TlsConnector::from(Arc::new(client));
    let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
    let name = rustls::pki_types::ServerName::try_from("localhost").unwrap();
    let mut stream = connector.connect(name, tcp).await.unwrap();
    assert!(get(&mut stream).await.starts_with("HTTP/1.1 401"));
}

#[tokio::test]
async fn serves_plain_http_in_development() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let (router, _dir) = app();
    tokio::spawn(serve_http(listener, router));
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    assert!(get(&mut stream).await.starts_with("HTTP/1.1 401"));
}

#[tokio::test]
async fn run_reports_startup_failures() {
    install_crypto();
    let dir = tempfile::tempdir().unwrap();
    let busy = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = Config {
        listen: busy.local_addr().unwrap(),
        state_dir: dir.path().into(),
        root: dir.path().into(),
        http: false,
    };
    let err = run(base.clone()).await.unwrap_err().to_string();
    if cfg!(feature = "dev-auth") || cfg!(target_os = "linux") {
        assert!(err.contains("cannot listen") || err.contains("no password helper"), "{err}");
        let free = Config { listen: "127.0.0.1:0".parse().unwrap(), ..base };
        let err = run(free).await.unwrap_err().to_string();
        assert!(err.contains("TLS") || err.contains("no password helper"), "{err}");
    } else {
        assert!(err.contains("needs Linux"), "{err}");
    }
}

#[test]
fn bind_reports_a_busy_port_and_keeps_explicit_addresses() {
    let busy = TcpListener::bind("127.0.0.1:0").unwrap();
    let err = bind(busy.local_addr().unwrap()).unwrap_err();
    assert!(err.to_string().contains("cannot listen"));
    assert!(bind("[::]:0".parse().unwrap()).is_ok(), "IPv6, or IPv4 without it");
}
