//! Docker for the Containers app, over the Engine API on Docker's unix
//! socket. Only the helper (root) talks to Docker; desktopd never holds the
//! socket (ADR-023). The requests are the fixed few below.

use std::path::PathBuf;
use std::time::Duration;

use http_body_util::{BodyExt, Empty};
use hyper::body::Bytes;
use hyper::{Method, Request, StatusCode};
use hyper_util::rt::TokioIo;
use kura_desktop_core::containers::{Container, ContainerAction, LogLine, parse_list, parse_logs};

use crate::Fut;

/// Docker's socket.
pub const SOCKET: &str = "/run/docker.sock";
/// How long Docker has to answer; a stop waits for the container first.
const TIMEOUT: Duration = Duration::from_secs(30);
/// Seconds a container gets to stop before Docker kills it.
const STOP_GRACE: u32 = 10;
/// The most of an answer that is read.
const MAX_BODY: usize = 4 << 20;

/// Why Docker did not do it.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DockerError {
    #[error("no such container")]
    NotFound,
    #[error("docker: {0}")]
    Unavailable(String),
}

/// What the helper asks of Docker.
pub trait Docker: Send + Sync {
    /// Every container, running or not.
    fn list(&self) -> Fut<'_, Result<Vec<Container>, DockerError>>;
    /// Starts, stops or restarts the container `id` (already validated).
    fn act<'a>(&'a self, id: &'a str, action: ContainerAction) -> Fut<'a, Result<(), DockerError>>;
    /// The last `lines` lines of the container's output.
    fn logs<'a>(&'a self, id: &'a str, lines: u32) -> Fut<'a, Result<Vec<LogLine>, DockerError>>;
}

/// The Engine API on a unix socket.
pub struct EngineDocker {
    socket: PathBuf,
}

impl Default for EngineDocker {
    fn default() -> Self {
        Self::new(SOCKET)
    }
}

impl EngineDocker {
    /// Docker listening on `socket`.
    pub fn new(socket: impl Into<PathBuf>) -> Self {
        Self { socket: socket.into() }
    }

    /// One request on its own connection; the answer's status and body (at
    /// most [`MAX_BODY`] bytes of it).
    async fn request(&self, method: Method, path: &str) -> Result<(StatusCode, Vec<u8>), DockerError> {
        let down = |e: &dyn std::fmt::Display| DockerError::Unavailable(e.to_string());
        let exchange = async {
            let stream = tokio::net::UnixStream::connect(&self.socket).await.map_err(|e| down(&e))?;
            let (mut sender, conn) =
                hyper::client::conn::http1::handshake(TokioIo::new(stream)).await.map_err(|e| down(&e))?;
            let conn = tokio::spawn(conn);
            let req = Request::builder().method(method).uri(path).header(hyper::header::HOST, "docker");
            let req = req.body(Empty::<Bytes>::new()).map_err(|e| down(&e))?;
            let res = sender.send_request(req).await.map_err(|e| down(&e))?;
            let status = res.status();
            let mut body = res.into_body();
            let mut bytes = Vec::new();
            while bytes.len() < MAX_BODY {
                match body.frame().await {
                    Some(Ok(frame)) => bytes.extend(frame.into_data().unwrap_or_default()),
                    Some(Err(e)) => return Err(down(&e)),
                    None => break,
                }
            }
            bytes.truncate(MAX_BODY);
            conn.abort();
            Ok((status, bytes))
        };
        tokio::time::timeout(TIMEOUT, exchange).await.map_err(|_| down(&"no answer in time"))?
    }
}

/// Docker's answer as a result: 404 is "no such container", any other
/// failure carries the status.
fn checked(status: StatusCode, body: Vec<u8>) -> Result<Vec<u8>, DockerError> {
    match status {
        // 304: already started or stopped, which is what was asked for.
        s if s.is_success() || s == StatusCode::NOT_MODIFIED => Ok(body),
        StatusCode::NOT_FOUND => Err(DockerError::NotFound),
        s => Err(DockerError::Unavailable(format!("answered {s}"))),
    }
}

impl Docker for EngineDocker {
    fn list(&self) -> Fut<'_, Result<Vec<Container>, DockerError>> {
        Box::pin(async {
            let (status, body) = self.request(Method::GET, "/containers/json?all=true").await?;
            parse_list(&checked(status, body)?).map_err(|e| DockerError::Unavailable(e.to_string()))
        })
    }

    fn act<'a>(&'a self, id: &'a str, action: ContainerAction) -> Fut<'a, Result<(), DockerError>> {
        Box::pin(async move {
            let grace = if action == ContainerAction::Start { String::new() } else { format!("?t={STOP_GRACE}") };
            let path = format!("/containers/{id}/{}{grace}", action.as_str());
            let (status, body) = self.request(Method::POST, &path).await?;
            checked(status, body).map(|_| ())
        })
    }

    fn logs<'a>(&'a self, id: &'a str, lines: u32) -> Fut<'a, Result<Vec<LogLine>, DockerError>> {
        Box::pin(async move {
            let path = format!("/containers/{id}/logs?stdout=true&stderr=true&timestamps=true&tail={lines}");
            let (status, body) = self.request(Method::GET, &path).await?;
            Ok(parse_logs(&checked(status, body)?))
        })
    }
}

#[cfg(test)]
mod tests;
