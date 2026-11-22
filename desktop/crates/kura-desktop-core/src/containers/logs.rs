//! Parsing a container's log stream as the Engine API sends it, and the
//! small text helpers that go with it.

use super::{LogLine, MAX_LINE_BYTES};

/// Parses `GET /containers/{id}/logs?timestamps=1`: Docker's multiplexed
/// stream (8-byte frame headers), or the raw text of a container with a TTY.
/// Colour codes are removed and lines cut at [`MAX_LINE_BYTES`].
pub fn parse_logs(body: &[u8]) -> Vec<LogLine> {
    let mut lines = Vec::new();
    let mut rest = body;
    // A frame header: the stream (0 to 2), three zero bytes, a big-endian length.
    while let [stream @ 0..=2, 0, 0, 0, a, b, c, d, tail @ ..] = rest {
        let len = (u32::from_be_bytes([*a, *b, *c, *d]) as usize).min(tail.len());
        push_lines(&mut lines, if *stream == 2 { "stderr" } else { "stdout" }, &tail[..len]);
        rest = &tail[len..];
    }
    // No header: a container with a TTY writes its output as it is.
    push_lines(&mut lines, "stdout", rest);
    lines
}

fn push_lines(lines: &mut Vec<LogLine>, stream: &'static str, chunk: &[u8]) {
    for raw in chunk.split(|b| *b == b'\n').filter(|l| !l.is_empty()) {
        let line = String::from_utf8_lossy(raw);
        let line = line.trim_end_matches('\r');
        let stamped = line.split_once(' ').and_then(|(stamp, text)| Some((Some(rfc3339_ms(stamp)?), text)));
        let (t, text) = stamped.unwrap_or((None, line));
        lines.push(LogLine { t, stream, text: cut(&clean(text), MAX_LINE_BYTES) });
    }
}

/// Text fit to show in a log view: colour codes (`ESC [ ... letter`) and
/// other control characters are removed, and so are the characters that
/// reorder text (U+202A to U+202E, U+2066 to U+2069), with which a log line
/// could pass for something else. Tabs stay.
pub fn clean(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            if chars.next() == Some('[') {
                // skip the parameters up to and including the final letter
                for p in chars.by_ref() {
                    if p.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
        } else if c == '\t' || !(c.is_control() || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')) {
            out.push(c);
        }
    }
    out
}

/// `text` cut to at most `max` bytes, at a character boundary.
pub fn cut(text: &str, max: usize) -> String {
    let mut end = text.len().min(max);
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    text[..end].to_owned()
}

/// Unix ms of a UTC RFC 3339 time such as `2026-11-21T10:00:00.123456789Z`,
/// as Docker stamps log lines; `None` for anything else.
pub(super) fn rfc3339_ms(text: &str) -> Option<i64> {
    let b = text.strip_suffix('Z')?;
    let (date, time) = b.split_once('T')?;
    let mut d = date.splitn(3, '-').map(|p| p.parse::<i64>().ok());
    let (y, m, day) = (d.next()??, d.next()??, d.next()??);
    let (clock, frac) = time.split_once('.').unwrap_or((time, ""));
    let mut c = clock.splitn(3, ':').map(|p| p.parse::<i64>().ok());
    let (h, min, s) = (c.next()??, c.next()??, c.next()??);
    let in_range = (1..=12).contains(&m) && (1..=31).contains(&day) && h < 24 && min < 60 && s < 61;
    if !in_range || date.len() != 10 || clock.len() != 8 || !frac.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let ms: i64 = format!("{frac:0<3}")[..3].parse().ok()?;
    // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + day - 1;
    let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468;
    Some(((days * 24 + h) * 60 + min) * 60_000 + s * 1000 + ms)
}
