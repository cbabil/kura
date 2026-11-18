#!/bin/bash
# tests/boot/desktop-checks.sh — Kura Desktop on a booted PC image (ADR-023):
# HTTPS on 443 (forwarded to HTTPS_PORT), the device's own certificate as the
# login screen shows it, sign-in through PAM with the login user's password,
# the CSRF rule, the server's memory, "desktop": false, and screenshots.
# Sourced by boot-test.sh after boot-checks.sh; defines functions only. The
# HTTP contract (body, headers, budget) is desktop/ci/api.sh's, shared with
# the server's own end-to-end test.
#
# Needs: HTTPS_PORT, LOGIN_USER, LOGIN_PASS, BRAND, OUT, and ssh_run,
# sudo_run, report_facts from boot-checks.sh.

# shellcheck source=desktop/ci/api.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../desktop/ci/api.sh"

DESKTOP_URL="https://127.0.0.1:${HTTPS_PORT}"
DESKTOP_WEB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../desktop/web" && pwd)"
DESKTOP_FP=""   # the device's certificate fingerprint, read once

login_code() { desktop_login_body "${LOGIN_USER}" "$1" | desktop_code "${DESKTOP_URL}" "${@:2}" "${DESKTOP_POST[@]}" "${DESKTOP_URL}/api/login"; }

desktop_https() { curl -sk --max-time 10 "${DESKTOP_URL}/" | grep -q '<div id="root">'; }

# The certificate served on 443 is the one whose fingerprint the device keeps
desktop_cert_matches() {
    local served
    served=$(openssl s_client -connect "127.0.0.1:${HTTPS_PORT}" </dev/null 2>/dev/null |
        openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
    DESKTOP_FP=$(sudo_run "cat /var/lib/${BRAND}/desktop/fingerprint")
    report_facts "served ${served:-none}"
    [ -n "${served}" ] && [ "${served}" = "${DESKTOP_FP}" ]
}

# ...and the login screen shows it (kura-issue redraws within a minute)
desktop_cert_shown() { [ -n "${DESKTOP_FP}" ] && ssh_run "grep -qF 'SHA-256 ${DESKTOP_FP:0:11}' /etc/issue"; }

# Sign-in with the login user's password (PAM, even where SSH refuses
# passwords), then the session cookie names the user
desktop_signin() {
    local jar="${OUT}/desktop-cookies"
    [ "$(login_code "${LOGIN_PASS}" "${DESKTOP_CHANGE[@]}" -c "${jar}")" = 200 ] && grep -q '__Host-kura' "${jar}" &&
        [ "$(curl -sk -b "${jar}" "${DESKTOP_URL}/api/session" | jq -r .user.name)" = "${LOGIN_USER}" ]
}

desktop_wrong_password_refused() { [ "$(login_code "wrong-${LOGIN_PASS}" "${DESKTOP_CHANGE[@]}")" = 401 ]; }

# Without X-Kura-Request a request that changes something is refused
desktop_csrf_refused() { [ "$(login_code "${LOGIN_PASS}")" = 403 ]; }

desktop_rss() {
    local kib
    kib=$(ssh_run "ps -o rss= -C ${BRAND}-desktopd" | head -1 | tr -d ' ')
    report_facts "kura-desktopd ${kib:-?} KiB resident"
    [ -n "${kib}" ] && [ "${kib}" -lt "${DESKTOP_RSS_MAX_KIB}" ]
}

# "desktop": false in the setup file: the server is off and nothing answers on 443
desktop_off() {
    [ "$(ssh_run "systemctl is-enabled ${BRAND}-desktopd" || true)" = disabled ] &&
        ! curl -sk --max-time 10 -o /dev/null "${DESKTOP_URL}/"
}

# signin.png and desktop.png through a real browser (Playwright's Chromium)
desktop_screens() {
    (cd "${DESKTOP_WEB}" &&
        KURA_DEVICE_URL="${DESKTOP_URL}" KURA_DEVICE_USER="${LOGIN_USER}" KURA_DEVICE_PASS="${LOGIN_PASS}" \
        KURA_DEVICE_SHOTS="${OUT}" bunx playwright test -c playwright.device.config.ts) > "${OUT}/desktop-screens.log" 2>&1 &&
        [ -s "${OUT}/signin.png" ] && [ -s "${OUT}/desktop.png" ]
}
