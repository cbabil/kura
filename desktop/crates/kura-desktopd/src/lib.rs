//! kura-desktopd: Kura Desktop's unprivileged server (ADR-023, ADR-024).
//!
//! It serves the embedded interface and the JSON API in
//! `desktop/web/src/api/client.ts` over HTTPS, keeps sign-in sessions in
//! memory, streams stats over a WebSocket, and asks `kura-helper` over D-Bus
//! to check passwords. It never holds the Docker socket.

// The fake password check must never reach an optimised (release) build.
#[cfg(all(feature = "dev-auth", not(debug_assertions)))]
compile_error!("the dev-auth feature is for debug builds only (make dev)");

pub mod app;
pub mod assets;
pub mod config;
pub mod helper;
pub mod server;
