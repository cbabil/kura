//! What a terminal may be, checked alike by desktopd and the helper.

/// The largest terminal, in columns or rows.
pub const MAX_CELLS: u16 = 500;

/// True for a terminal of 1 to [`MAX_CELLS`] columns and rows.
pub fn valid_size(cols: u16, rows: u16) -> bool {
    (1..=MAX_CELLS).contains(&cols) && (1..=MAX_CELLS).contains(&rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes() {
        for (cols, rows, want) in [
            (80, 24, true),
            (1, 1, true),
            (500, 500, true),
            (0, 24, false),
            (80, 0, false),
            (501, 24, false),
            (80, 501, false),
        ] {
            assert_eq!(valid_size(cols, rows), want, "{cols}x{rows}");
        }
    }
}
