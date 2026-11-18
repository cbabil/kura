//! Embeds the built interface (`desktop/web/dist`, or `KURA_WEB_DIST`) into
//! the binary. Without it the server shows a placeholder page.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=KURA_WEB_DIST");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("set by cargo"));
    let dist = std::env::var_os("KURA_WEB_DIST").map(PathBuf::from).unwrap_or_else(|| manifest.join("../../web/dist"));
    println!("cargo:rerun-if-changed={}", dist.display());
    let mut files = Vec::new();
    if dist.is_dir() {
        collect(&dist, &dist, &mut files);
    }
    files.sort();
    let mut code =
        String::from("/// Embedded interface files: (URL path, bytes).\npub static ASSETS: &[(&str, &[u8])] = &[\n");
    for (url, path) in &files {
        println!("cargo:rerun-if-changed={}", path.display());
        writeln!(code, "    ({url:?}, include_bytes!({:?})),", path.display().to_string()).expect("string write");
    }
    code.push_str("];\n");
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("set by cargo")).join("assets.rs");
    std::fs::write(out, code).expect("OUT_DIR is writable");
}

fn collect(base: &Path, dir: &Path, files: &mut Vec<(String, PathBuf)>) {
    let entries = std::fs::read_dir(dir).expect("dist is readable");
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(base, &path, files);
        } else if let Ok(rel) = path.strip_prefix(base) {
            let url = format!("/{}", rel.to_string_lossy().replace('\\', "/"));
            files.push((url, path.canonicalize().expect("dist file exists")));
        }
    }
}
