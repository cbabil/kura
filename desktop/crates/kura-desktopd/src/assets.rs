//! The embedded interface: files from `desktop/web/dist`, with the single-page
//! fallback to `index.html` and long caching for hashed `/assets/` files.

use axum::http::{HeaderValue, StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};

include!(concat!(env!("OUT_DIR"), "/assets.rs"));

/// Shown when the binary was built without the interface.
const PLACEHOLDER: &str = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Kura</title></head>\
<body><h1>Kura Desktop</h1><p>This build has no interface. Run <code>make -C desktop web</code> and rebuild.</p></body></html>";

/// A set of embedded files, as `(path, bytes)` sorted by path.
pub type Files = &'static [(&'static str, &'static [u8])];

/// The content type for a file name.
fn content_type(path: &str) -> &'static str {
    match path.rsplit('.').next().unwrap_or("") {
        "html" => "text/html; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "ico" => "image/x-icon",
        "json" | "webmanifest" => "application/json",
        "woff2" => "font/woff2",
        "woff" => "font/woff",
        "txt" => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}

fn find(files: Files, path: &str) -> Option<&'static [u8]> {
    files.binary_search_by(|(p, _)| (*p).cmp(path)).ok().map(|i| files[i].1)
}

/// Serves `uri` from `files`. Paths without a file extension fall back to
/// `index.html`, so the interface can own its routes.
pub fn serve(files: Files, uri: &Uri) -> Response {
    let path = match uri.path() {
        "/" => "/index.html",
        p => p,
    };
    let looks_like_file = path.rsplit('/').next().is_some_and(|last| last.contains('.'));
    let found = find(files, path).map(|b| (path, b));
    let found =
        found.or_else(|| (!looks_like_file).then(|| find(files, "/index.html").map(|b| ("/index.html", b))).flatten());
    match found {
        Some((served, body)) => {
            let cache = if served.starts_with("/assets/") { "public, max-age=31536000, immutable" } else { "no-cache" };
            let headers = [(header::CONTENT_TYPE, content_type(served)), (header::CACHE_CONTROL, cache)];
            (headers, body).into_response()
        }
        None if files.is_empty() => {
            ([(header::CONTENT_TYPE, HeaderValue::from_static("text/html; charset=utf-8"))], PLACEHOLDER)
                .into_response()
        }
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    static FILES: Files = &[("/assets/app-1a2b.js", b"js"), ("/favicon.svg", b"<svg/>"), ("/index.html", b"<html>")];

    fn get(files: Files, path: &str) -> Response {
        serve(files, &path.parse().unwrap())
    }

    #[test]
    fn serves_files_with_types_and_caching() {
        let cases = [
            ("/", StatusCode::OK, "text/html; charset=utf-8", "no-cache"),
            (
                "/assets/app-1a2b.js",
                StatusCode::OK,
                "text/javascript; charset=utf-8",
                "public, max-age=31536000, immutable",
            ),
            ("/favicon.svg", StatusCode::OK, "image/svg+xml", "no-cache"),
            ("/some/route", StatusCode::OK, "text/html; charset=utf-8", "no-cache"),
        ];
        for (path, status, ty, cache) in cases {
            let r = get(FILES, path);
            assert_eq!(r.status(), status, "{path}");
            assert_eq!(r.headers()[header::CONTENT_TYPE], ty, "{path}");
            assert_eq!(r.headers()[header::CACHE_CONTROL], cache, "{path}");
        }
        assert_eq!(get(FILES, "/missing.js").status(), StatusCode::NOT_FOUND);
    }

    #[test]
    fn placeholder_without_an_interface() {
        let r = get(&[], "/");
        assert_eq!(r.status(), StatusCode::OK);
        assert_eq!(get(&[], "/x.js").status(), StatusCode::OK);
    }

    #[test]
    fn content_types() {
        let cases = [
            ("a.css", "text/css; charset=utf-8"),
            ("a.png", "image/png"),
            ("a.woff2", "font/woff2"),
            ("a.woff", "font/woff"),
            ("a.ico", "image/x-icon"),
            ("a.json", "application/json"),
            ("a.txt", "text/plain; charset=utf-8"),
            ("a.bin", "application/octet-stream"),
        ];
        for (name, want) in cases {
            assert_eq!(content_type(name), want);
        }
        assert!(ASSETS.windows(2).all(|w| w[0].0 < w[1].0), "build.rs sorts the files");
    }
}
