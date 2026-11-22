//! `kura-agent`: started by systemd as the signed-in user, with a socket to
//! `kura-desktopd` as its input and output. It ends when the socket closes.

use std::process::ExitCode;

fn main() -> ExitCode {
    let Some(home) = std::env::var_os("HOME").and_then(|h| h.into_string().ok()) else {
        eprintln!("kura-agent: no home folder");
        return ExitCode::FAILURE;
    };
    let agent = kura_agent::Agent::new(home);
    match agent.serve(&mut std::io::stdin().lock(), &mut std::io::stdout().lock()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("kura-agent: {e}");
            ExitCode::FAILURE
        }
    }
}
