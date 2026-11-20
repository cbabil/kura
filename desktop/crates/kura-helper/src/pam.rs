//! The real [`Pam`]: Linux-PAM through its C API, service `login`. Linked
//! against `libpam.so.0`; proven by the Linux CI job with a throwaway user.

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;

use zeroize::Zeroizing;

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
const PAM_TTY: c_int = 3;
const PAM_FAIL_DELAY: c_int = 10;
/// What `PAM_TTY` says, so modules and logs can tell these sign-ins apart.
const TTY: &CStr = c"kura-desktop";

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
    fn pam_set_item(pamh: *mut c_void, item_type: c_int, item: *const c_void) -> c_int;
}

/// Replaces `pam_faildelay`'s sleep: a sleeping check would hold the helper's
/// one-at-a-time lock, so desktopd delays failures instead.
unsafe extern "C" fn no_fail_delay(_status: c_int, _usec: std::ffi::c_uint, _data: *mut c_void) {}

/// What the conversation answers with.
struct Answers {
    user: CString,
    /// Wiped when the check is over.
    password: Zeroizing<CString>,
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
                PAM_PROMPT_ECHO_OFF => Some(&*answers.password),
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

/// The PAM service: `login`, so sign-in behaves as at the console.
const SERVICE: &CStr = c"login";

/// Linux-PAM with the [`SERVICE`] service.
#[derive(Debug, Default)]
pub struct LinuxPam;

impl LinuxPam {
    fn transaction(&self, answers: &Answers) -> PamVerdict {
        let conv = PamConv { conv: converse, appdata_ptr: answers as *const Answers as *mut c_void };
        let mut handle: *mut c_void = ptr::null_mut();
        // SAFETY: every pointer outlives the transaction, and `pam_end` is
        // called on every path once `pam_start` succeeded.
        unsafe {
            if pam_start(SERVICE.as_ptr(), answers.user.as_ptr(), &conv, &mut handle) != PAM_SUCCESS {
                return PamVerdict::Wrong;
            }
            let delay: unsafe extern "C" fn(c_int, std::ffi::c_uint, *mut c_void) = no_fail_delay;
            pam_set_item(handle, PAM_FAIL_DELAY, delay as *const c_void);
            pam_set_item(handle, PAM_TTY, TTY.as_ptr().cast());
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
        self.transaction(&Answers { user, password: Zeroizing::new(password) })
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
    /// `KURA_PAM_PASSWORD`, and `KURA_PAM_EXPIRED_USER` with the same
    /// password, which must be changed.
    #[test]
    #[ignore = "needs root and throwaway users: make test-pam"]
    fn checks_a_real_user() {
        let var = |name: &str| std::env::var(name).unwrap_or_else(|_| panic!("{name} is not set"));
        let (user, password, expired) = (var("KURA_PAM_USER"), var("KURA_PAM_PASSWORD"), var("KURA_PAM_EXPIRED_USER"));
        let pam = LinuxPam;
        assert_eq!(pam.check(&user, &password), PamVerdict::Ok);
        assert_eq!(pam.check(&user, "definitely-wrong"), PamVerdict::Wrong);
        assert_eq!(pam.check("no-such-user-kura", &password), PamVerdict::Wrong);
        assert_eq!(pam.check(&expired, &password), PamVerdict::Expired);
    }
}
