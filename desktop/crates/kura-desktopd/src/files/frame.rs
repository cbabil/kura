//! Frames on the socket to an agent, as `kura_desktop_core::files` reads
//! and writes them on the agent's side: four bytes of length, then the bytes.

use std::io;

use kura_desktop_core::files::MAX_FRAME;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;

pub(super) async fn send(stream: &mut UnixStream, bytes: &[u8]) -> io::Result<()> {
    let length = u32::try_from(bytes.len()).ok().filter(|_| bytes.len() <= MAX_FRAME);
    let length = length.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "frame too long"))?;
    stream.write_all(&length.to_be_bytes()).await?;
    stream.write_all(bytes).await
}

pub(super) async fn receive(stream: &mut UnixStream) -> io::Result<Vec<u8>> {
    let length = stream.read_u32().await? as usize;
    if length > MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too long"));
    }
    let mut bytes = vec![0u8; length];
    stream.read_exact(&mut bytes).await?;
    Ok(bytes)
}
