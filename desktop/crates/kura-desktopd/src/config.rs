//! Command-line settings for kura-desktopd.

use std::net::SocketAddr;
use std::path::PathBuf;

/// Where desktopd keeps its certificate and preferences.
pub const STATE_DIR: &str = "/var/lib/kura/desktop";
/// The environment variable the systemd unit sets to the state folder.
pub const STATE_DIR_ENV: &str = "KURA_STATE_DIR";
/// The environment variable that overrides the listen address (development).
pub const LISTEN_ENV: &str = "KURA_DESKTOP_LISTEN";

/// Settings from the environment: [`STATE_DIR_ENV`] and [`LISTEN_ENV`].
#[derive(Debug, Clone, Default)]
pub struct Env {
    pub state_dir: Option<String>,
    pub listen: Option<String>,
}

impl Env {
    /// Reads the variables of this process; empty ones count as unset.
    pub fn from_process() -> Self {
        let var = |name| std::env::var(name).ok().filter(|v: &String| !v.is_empty());
        Self { state_dir: var(STATE_DIR_ENV), listen: var(LISTEN_ENV) }
    }
}

/// The parsed command line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    /// The socket to listen on; `[::]:443` by default (IPv4 and IPv6).
    pub listen: SocketAddr,
    /// Holds `tls.crt`, `tls.key` and `prefs/`.
    pub state_dir: PathBuf,
    /// Where `/proc`, `/sys` and `/etc` are read; `/` except in development.
    pub root: PathBuf,
    /// Plain HTTP instead of HTTPS; only with the `dev-auth` feature.
    pub http: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            listen: SocketAddr::from(([0u16; 8], 443)),
            state_dir: PathBuf::from(STATE_DIR),
            root: PathBuf::from("/"),
            http: false,
        }
    }
}

/// The usage text shown for `--help` and bad arguments.
pub const USAGE: &str =
    "usage: kura-desktopd [--listen ADDR:PORT] [--state-dir DIR] [--root DIR] [--http (dev-auth builds only)]";

impl Config {
    /// Parses arguments (without the program name). A flag wins over the
    /// environment, which wins over the defaults.
    ///
    /// # Errors
    /// Returns a message for an unknown flag, a missing or bad value, or
    /// `--http` in a build without `dev-auth`.
    pub fn parse(args: impl IntoIterator<Item = String>, env: &Env) -> Result<Self, String> {
        let mut config = Self::default();
        if let Some(dir) = &env.state_dir {
            config.state_dir = dir.into();
        }
        if let Some(addr) = &env.listen {
            config.listen = addr.parse().map_err(|e| format!("{LISTEN_ENV}: {e}"))?;
        }
        let mut args = args.into_iter();
        while let Some(flag) = args.next() {
            let mut value = || args.next().ok_or_else(|| format!("{flag} needs a value"));
            match flag.as_str() {
                "--listen" => config.listen = value()?.parse().map_err(|e| format!("--listen: {e}"))?,
                "--state-dir" => config.state_dir = value()?.into(),
                "--root" => config.root = value()?.into(),
                "--http" if cfg!(feature = "dev-auth") => config.http = true,
                "--http" => return Err("--http needs a dev-auth build".into()),
                other => return Err(format!("unknown argument {other:?}\n{USAGE}")),
            }
        }
        Ok(config)
    }

    /// The certificate and key paths.
    pub fn tls_files(&self) -> (PathBuf, PathBuf) {
        (self.state_dir.join("tls.crt"), self.state_dir.join("tls.key"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(args: &[&str]) -> Result<Config, String> {
        Config::parse(args.iter().map(|s| (*s).to_owned()), &Env::default())
    }

    #[test]
    fn defaults_and_flags() {
        assert_eq!(parse(&[]).unwrap(), Config::default());
        assert_eq!(Config::default().listen.to_string(), "[::]:443");
        let c = parse(&["--listen", "127.0.0.1:8443", "--state-dir", "/tmp/s", "--root", "/tmp/r"]).unwrap();
        assert_eq!(c.listen.port(), 8443);
        assert_eq!(c.tls_files().0, PathBuf::from("/tmp/s/tls.crt"));
        assert_eq!(c.root, PathBuf::from("/tmp/r"));
    }

    #[test]
    fn the_environment_unless_a_flag_is_given() {
        let env = Env { state_dir: Some("/srv/state".into()), listen: Some("127.0.0.1:8443".into()) };
        let args = |a: &[&str]| a.iter().map(|s| (*s).to_owned()).collect::<Vec<_>>();
        let c = Config::parse(args(&[]), &env).unwrap();
        assert_eq!((c.state_dir, c.listen.port()), (PathBuf::from("/srv/state"), 8443));
        let c = Config::parse(args(&["--state-dir", "/x", "--listen", "[::1]:9"]), &env).unwrap();
        assert_eq!((c.state_dir, c.listen.port()), (PathBuf::from("/x"), 9));
        let bad = Env { listen: Some("nope".into()), ..Env::default() };
        assert!(Config::parse(args(&[]), &bad).unwrap_err().contains(LISTEN_ENV));
        let _ = Env::from_process();
    }

    #[test]
    fn bad_arguments() {
        for (args, want) in
            [(&["--listen"][..], "needs a value"), (&["--listen", "x"], "--listen"), (&["--nope"], "unknown")]
        {
            assert!(parse(args).unwrap_err().contains(want), "{args:?}");
        }
        let http = parse(&["--http"]);
        assert_eq!(http.is_ok(), cfg!(feature = "dev-auth"));
    }
}
