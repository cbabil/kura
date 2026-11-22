//! Frames: four bytes of length, most significant first, then that many
//! bytes.

use std::io::{self, Read, Write};

/// The longest frame either side accepts.
pub const MAX_FRAME: usize = 4 * 1024 * 1024;

/// Writes one frame.
///
/// # Errors
/// Fails for a frame over [`MAX_FRAME`] and when the writer does.
pub fn write_frame(to: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
    if bytes.len() > MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too long"));
    }
    // The length fits: MAX_FRAME is far below u32::MAX.
    to.write_all(&(bytes.len() as u32).to_be_bytes())?;
    to.write_all(bytes)?;
    to.flush()
}

/// Reads one frame; `None` when the other side closed between frames.
///
/// # Errors
/// Fails for a frame over [`MAX_FRAME`], one cut short, and when the reader
/// does.
pub fn read_frame(from: &mut impl Read) -> io::Result<Option<Vec<u8>>> {
    let mut length = [0u8; 4];
    let mut got = 0;
    while got < length.len() {
        match from.read(&mut length[got..]) {
            Ok(0) if got == 0 => return Ok(None),
            Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
            Ok(n) => got += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    let length = u32::from_be_bytes(length) as usize;
    if length > MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too long"));
    }
    let mut bytes = vec![0u8; length];
    from.read_exact(&mut bytes)?;
    Ok(Some(bytes))
}
