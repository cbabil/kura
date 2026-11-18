//! The real [`Pam`]: Linux-PAM through its C API, service `login`. Linked
//! against `libpam.so.0`; proven by the Linux CI job with a throwaway user.

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;

use zeroize::Zeroize;

use crate::authenticate::{Pam, PamVerdict};

const PAM_SUCCESS: c_int = 0;
const PAM_BUF_ERR: c_int = 5;
const PAM_CONV_ERR: c_int = 19;
const PAM_NEW_AUTHTOK_REQD: c_int = 12;
const PAM_PROMPT_ECHO_OFF: c_int = 1;
const PAM_PROMPT_ECHO_ON: c_int = 2;
const PAM_SILENT: c_int = 0x8000;
const PAM_DISALLOW_NULL_AUTHTOK: c_int = 0x1;
const PAM_MAX_NUM_MSG: c_int = 32;

#[repr(C)]
struct PamMessage {
    msg_style: c_int,
    msg: *const c_char,
}

#[repr(C)]
struct PamResponse {
    resp: *mut c_char,
    resp_retcode: c_int,
}

type ConvFn = unsafe extern "C" fn(c_int, *mut *const PamMessage, *mut *mut PamResponse, *mut c_void) -> c_int;

#[repr(C)]
struct PamConv {
    conv: ConvFn,
    appdata_ptr: *mut c_void,
}

#[link(name = "pam")]
unsafe extern "C" {
    fn pam_start(service: *const c_char, user: *const c_char, conv: *const PamConv, pamh: *mut *mut c_void) -> c_int;
    fn pam_authenticate(pamh: *mut c_void, flags: c_int) -> c_int;
    fn pam_acct_mgmt(pamh: *mut c_void, flags: c_int) -> c_int;
    fn pam_end(pamh: *mut c_void, status: c_int) -> c_int;
}

/// What the conversation answers with.
struct Answers {
    user: CString,
    password: CString,
}

/// Answers PAM's prompts: the password for hidden prompts, the user name for
/// visible ones, nothing for messages. Responses are `calloc`ed because PAM
/// frees them.
unsafe extern "C" fn converse(
    n: c_int,
    msgs: *mut *const PamMessage,
    out: *mut *mut PamResponse,
    data: *mut c_void,
) -> c_int {
    if n <= 0 || n > PAM_MAX_NUM_MSG || msgs.is_null() || out.is_null() || data.is_null() {
        return PAM_CONV_ERR;
    }
    // SAFETY: PAM passes back the `Answers` given to `pam_start`, alive for
    // the whole transaction, and `n` valid message pointers (Linux-PAM layout).
    unsafe {
        let answers = &*(data as *const Answers);
        let replies = libc::calloc(n as usize, size_of::<PamResponse>()) as *mut PamResponse;
        if replies.is_null() {
            return PAM_BUF_ERR;
        }
        for i in 0..n as usize {
            let msg = *msgs.add(i);
            let text = match (*msg).msg_style {
                PAM_PROMPT_ECHO_OFF => Some(&answers.password),
                PAM_PROMPT_ECHO_ON => Some(&answers.user),
                _ => None,
            };
            if let Some(text) = text {
                (*replies.add(i)).resp = libc::strdup(text.as_ptr());
            }
        }
        *out = replies;
    }
    PAM_SUCCESS
}

/// Linux-PAM with a fixed service name.
pub struct LinuxPam {
    service: CString,
}

impl LinuxPam {
    /// PAM with the `login` service, as at the console.
    pub fn login() -> Self {
        Self { service: CString::from(c"login") }
    }

    fn transaction(&self, answers: &Answers) -> PamVerdict {
        let conv = PamConv { conv: converse, appdata_ptr: answers as *const Answers as *mut c_void };
        let mut handle: *mut c_void = ptr::null_mut();
        // SAFETY: every pointer outlives the transaction, and `pam_end` is
        // called on every path once `pam_start` succeeded.
        unsafe {
            if pam_start(self.service.as_ptr(), answers.user.as_ptr(), &conv, &mut handle) != PAM_SUCCESS {
                return PamVerdict::Wrong;
            }
            let mut status = pam_authenticate(handle, PAM_SILENT | PAM_DISALLOW_NULL_AUTHTOK);
            let verdict = if status != PAM_SUCCESS {
                PamVerdict::Wrong
            } else {
                status = pam_acct_mgmt(handle, PAM_SILENT | PAM_DISALLOW_NULL_AUTHTOK);
                verdict_for_account(status)
            };
            pam_end(handle, status);
            verdict
        }
    }
}

/// Maps `pam_acct_mgmt`'s result.
fn verdict_for_account(status: c_int) -> PamVerdict {
    match status {
        PAM_SUCCESS => PamVerdict::Ok,
        PAM_NEW_AUTHTOK_REQD => PamVerdict::Expired,
        _ => PamVerdict::Wrong,
    }
}

impl Pam for LinuxPam {
    fn check(&self, user: &str, password: &str) -> PamVerdict {
        let (Ok(user), Ok(password)) = (CString::new(user), CString::new(password)) else {
            return PamVerdict::Wrong;
        };
        let answers = Answers { user, password };
        let verdict = self.transaction(&answers);
        let mut secret = answers.password.into_bytes_with_nul();
        secret.zeroize();
        verdict
    }
}

/// Shows the service in logs.
impl std::fmt::Debug for LinuxPam {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let service: &CStr = &self.service;
        write!(f, "LinuxPam({service:?})")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn account_results() {
        assert_eq!(verdict_for_account(PAM_SUCCESS), PamVerdict::Ok);
        assert_eq!(verdict_for_account(PAM_NEW_AUTHTOK_REQD), PamVerdict::Expired);
        assert_eq!(verdict_for_account(13), PamVerdict::Wrong);
    }

    /// Needs root and users made by the CI job: `KURA_PAM_USER` with password
    /// `KURA_PAM_PASSWORD`, and optionally `KURA_PAM_EXPIRED_USER` with the
    /// same password, which must be changed.
    #[test]
    fn checks_a_real_user() {
        let (Ok(user), Ok(password)) = (std::env::var("KURA_PAM_USER"), std::env::var("KURA_PAM_PASSWORD")) else {
            return;
        };
        let pam = LinuxPam::login();
        assert_eq!(pam.check(&user, &password), PamVerdict::Ok);
        assert_eq!(pam.check(&user, "definitely-wrong"), PamVerdict::Wrong);
        assert_eq!(pam.check("no-such-user-kura", &password), PamVerdict::Wrong);
        assert!(format!("{pam:?}").contains("login"));
        if let Ok(expired) = std::env::var("KURA_PAM_EXPIRED_USER") {
            assert_eq!(pam.check(&expired, &password), PamVerdict::Expired);
        }
    }
}
