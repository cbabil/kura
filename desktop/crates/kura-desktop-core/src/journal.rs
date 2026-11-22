//! The system journal as the Console app shows it: a validated query that
//! becomes `journalctl` arguments, and a parser for `journalctl -o json`.
//! The helper runs journalctl; desktopd only passes the page on.

use std::collections::HashMap;

use serde::Serialize;
use serde_json::Value;

use crate::containers::{clean, cut};

/// The most entries one request may ask for.
pub const MAX_LINES: u32 = 1000;
/// The longest message kept, in bytes.
pub const MAX_MESSAGE_BYTES: usize = 4096;

/// Why a query was refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum QueryError {
    #[error("lines must be 1 to 1000")]
    Lines,
    #[error("not a unit name")]
    Unit,
    #[error("priority must be 0 to 7")]
    Priority,
    #[error("not a journal cursor")]
    Cursor,
}

/// A checked journal query. Only [`JournalQuery::new`] makes one, so every
/// value in [`JournalQuery::to_args`] is a plain filter and never an option.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JournalQuery {
    lines: u32,
    unit: Option<String>,
    priority: Option<u8>,
    after: Option<String>,
}

impl JournalQuery {
    /// Checks a query as it comes over the wire: an empty `unit` or `after`
    /// and a `priority` of -1 mean "no filter".
    ///
    /// # Errors
    /// See [`QueryError`].
    pub fn new(lines: u32, unit: &str, priority: i32, after: &str) -> Result<Self, QueryError> {
        let unit_ok = unit.len() <= 255
            && !unit.starts_with('-')
            && unit.bytes().all(|b| b.is_ascii_alphanumeric() || b":_.@\\-".contains(&b));
        let cursor_ok = after.len() <= 512
            && !after.starts_with('-')
            && after.bytes().all(|b| b.is_ascii_alphanumeric() || b"=;".contains(&b));
        if !(1..=MAX_LINES).contains(&lines) {
            return Err(QueryError::Lines);
        }
        if !unit_ok {
            return Err(QueryError::Unit);
        }
        if !(-1..=7).contains(&priority) {
            return Err(QueryError::Priority);
        }
        if !cursor_ok {
            return Err(QueryError::Cursor);
        }
        Ok(Self {
            lines,
            unit: Some(unit.to_owned()).filter(|u| !u.is_empty()),
            priority: u8::try_from(priority).ok(),
            after: Some(after.to_owned()).filter(|a| !a.is_empty()),
        })
    }

    /// How many entries, at most.
    pub fn lines(&self) -> u32 {
        self.lines
    }

    /// The unit asked for, if one.
    pub fn unit(&self) -> Option<&str> {
        self.unit.as_deref()
    }

    /// The least serious priority asked for, if one.
    pub fn priority(&self) -> Option<u8> {
        self.priority
    }

    /// The cursor to start after, if one.
    pub fn after(&self) -> Option<&str> {
        self.after.as_deref()
    }

    /// The arguments for `journalctl`: the newest `lines` entries that match,
    /// oldest first, as JSON.
    pub fn to_args(&self) -> Vec<String> {
        // --all: without it a field over 4096 bytes comes as null.
        let mut args: Vec<String> = ["--output=json", "--all", "--no-pager", "--quiet"].map(String::from).into();
        args.push(format!("--lines={}", self.lines));
        args.extend(self.unit.iter().map(|u| format!("--unit={u}")));
        args.extend(self.priority.iter().map(|p| format!("--priority={p}")));
        args.extend(self.after.iter().map(|a| format!("--after-cursor={a}")));
        args
    }
}

/// One journal entry, as `JournalEntry` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct JournalEntry {
    /// Unix ms.
    pub t: i64,
    /// syslog priority, 0 (emergency) to 7 (debug); 6 when the entry has none.
    pub priority: u8,
    /// The systemd unit, or "".
    pub unit: String,
    /// The program's name, or "".
    pub ident: String,
    pub pid: Option<u32>,
    pub message: String,
}

/// Entries and the cursor to ask for what comes after them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct JournalPage {
    pub entries: Vec<JournalEntry>,
    pub cursor: Option<String>,
}

/// Parses `journalctl --output=json`: one object per line; lines that are
/// not JSON are skipped.
pub fn parse_page(stdout: &[u8]) -> JournalPage {
    let mut page = JournalPage { entries: Vec::new(), cursor: None };
    for line in stdout.split(|b| *b == b'\n') {
        let Ok(raw) = serde_json::from_slice::<HashMap<String, Value>>(line) else { continue };
        let text = |key: &str| raw.get(key).and_then(Value::as_str);
        if let Some(cursor) = text("__CURSOR") {
            page.cursor = Some(cursor.to_owned());
        }
        page.entries.push(JournalEntry {
            t: text("__REALTIME_TIMESTAMP").and_then(|us| us.parse::<i64>().ok()).unwrap_or(0) / 1000,
            priority: text("PRIORITY").and_then(|p| p.parse().ok()).filter(|p| *p <= 7).unwrap_or(6),
            unit: text("_SYSTEMD_UNIT").or(text("UNIT")).unwrap_or("").to_owned(),
            ident: text("SYSLOG_IDENTIFIER").or(text("_COMM")).unwrap_or("").to_owned(),
            pid: text("_PID").and_then(|p| p.parse().ok()),
            message: cut(&clean(&message(raw.get("MESSAGE"))), MAX_MESSAGE_BYTES),
        });
    }
    page
}

/// journald gives a message that is not UTF-8 as an array of bytes.
fn message(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(bytes)) => {
            let bytes: Vec<u8> = bytes.iter().filter_map(|b| b.as_u64().and_then(|b| u8::try_from(b).ok())).collect();
            String::from_utf8_lossy(&bytes).into_owned()
        }
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests;
