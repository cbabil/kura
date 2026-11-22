//! Docker containers as the Containers app shows them: the shapes of
//! `Container` and `LogLine` in types.ts, the fixed actions, and parsers for
//! the Engine API's list and log stream. The helper talks to Docker; desktopd
//! only passes these on.

mod logs;

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

#[cfg(test)]
use logs::rfc3339_ms;
pub use logs::{clean, cut, parse_logs};

/// The longest log line kept, in bytes; the rest of a line is dropped.
pub const MAX_LINE_BYTES: usize = 4096;
/// The most log lines one request may ask for.
pub const MAX_LOG_LINES: u32 = 1000;

/// A container, as `Container` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Container {
    pub id: String,
    pub name: String,
    pub image: String,
    /// Docker's state: running, exited, paused, restarting, created, dead.
    pub state: String,
    /// Docker's own words, e.g. "Up 3 days" or "Exited (0) 2 hours ago".
    pub status: String,
    /// Unix ms the container was created.
    pub created: i64,
    /// The compose project and service, when compose made it.
    pub project: Option<String>,
    pub service: Option<String>,
    /// Published host ports, sorted, each once.
    pub ports: Vec<u16>,
}

/// What may be done to a container: the whole list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContainerAction {
    Start,
    Stop,
    Restart,
}

impl ContainerAction {
    /// Reads "start", "stop" or "restart"; anything else is `None`.
    pub fn parse(text: &str) -> Option<Self> {
        [Self::Start, Self::Stop, Self::Restart].into_iter().find(|a| a.as_str() == text)
    }

    /// The action's name, as in the Engine API's path.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Start => "start",
            Self::Stop => "stop",
            Self::Restart => "restart",
        }
    }
}

/// True for a container id as Docker prints it: 12 to 64 lowercase hex
/// digits. Names are not accepted, so nothing else can reach a request path.
pub fn valid_container_id(id: &str) -> bool {
    (12..=64).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// One line of a container's output, as `LogLine` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LogLine {
    /// Unix ms, or `None` when the line carries no timestamp.
    pub t: Option<i64>,
    /// "stdout" or "stderr".
    pub stream: &'static str,
    pub text: String,
}

/// Parses `GET /containers/json`.
///
/// # Errors
/// Fails when the body is not the JSON Docker documents.
pub fn parse_list(body: &[u8]) -> Result<Vec<Container>, serde_json::Error> {
    let raw: Vec<RawContainer> = serde_json::from_slice(body)?;
    Ok(raw.into_iter().map(Container::from).collect())
}

/// One entry of the Engine API's list, reduced to what is shown.
#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RawContainer {
    id: String,
    #[serde(default)]
    names: Vec<String>,
    #[serde(default)]
    image: String,
    #[serde(default)]
    state: String,
    #[serde(default)]
    status: String,
    #[serde(default)]
    created: i64,
    #[serde(default)]
    labels: Option<HashMap<String, String>>,
    #[serde(default)]
    ports: Option<Vec<RawPort>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RawPort {
    public_port: Option<u16>,
}

impl From<RawContainer> for Container {
    fn from(raw: RawContainer) -> Self {
        let mut labels = raw.labels.unwrap_or_default();
        let mut ports: Vec<u16> = raw.ports.unwrap_or_default().iter().filter_map(|p| p.public_port).collect();
        ports.sort_unstable();
        ports.dedup();
        // Docker names start with "/"; a container without one shows its short id.
        let name = raw.names.first().map(|n| n.trim_start_matches('/').to_owned()).filter(|n| !n.is_empty());
        Self {
            name: name.unwrap_or_else(|| raw.id.chars().take(12).collect()),
            id: raw.id,
            image: raw.image,
            state: raw.state,
            status: raw.status,
            created: raw.created.saturating_mul(1000),
            project: labels.remove("com.docker.compose.project"),
            service: labels.remove("com.docker.compose.service"),
            ports,
        }
    }
}

#[cfg(test)]
mod tests;
