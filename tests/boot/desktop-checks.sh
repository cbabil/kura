#!/bin/bash
# tests/boot/desktop-checks.sh — Kura Desktop on a booted PC image (ADR-023):
# HTTPS on 443 (forwarded to HTTPS_PORT), the device's own certificate as the
# login screen shows it, sign-in through PAM with the login user's password,
# the CSRF rule, the server's memory, "desktop": false, the helper's Docker
# and journal answers (ADR-027), and screenshots, of a terminal too.
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

# The helper asks Docker for the containers: a list, empty on a fresh image
# (uses the cookie desktop_signin kept)
desktop_containers() { [ "$(curl -sk --max-time 10 -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/containers" | jq -r type)" = array ]; }

# ...and reads the journal for an administrator
desktop_journal() {
    local entries
    entries=$(curl -sk --max-time 20 -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/journal?lines=5" | jq '.entries | length')
    report_facts "${entries:-no} journal entries"
    [ "${entries:-0}" -ge 1 ]
}

# The desktop knows the version it runs, as the login screen does
desktop_version() {
    local shown
    shown=$(curl -sk --max-time 20 -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/updates" | jq -r .current)
    report_facts "desktop says Kura ${shown:-?}"
    [ -n "${shown}" ] && ssh_run "grep -qF 'BRAND_VERSION=\"${shown}\"' /usr/lib/${BRAND}/release"
}

# Settings come from the helper: the host name, the login user as an
# administrator, the clock's zone
desktop_settings() {
    curl -sk --max-time 20 -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/settings" | jq -e --arg u "${LOGIN_USER}" \
        '(.hostname | length > 0) and (.time.zone | length > 0) and any(.users[]; .name == $u and .admin)' >/dev/null
}

# ...and a change runs through the root command: the zone is set to the one it has
desktop_setting_changes() {
    local zone
    zone=$(curl -sk --max-time 20 -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/settings" | jq -r .time.zone)
    [ -n "${zone}" ] && [ "$(jq -nc --arg z "${zone}" '{what: "timezone", zone: $z}' |
        desktop_code "${DESKTOP_URL}" -b "${OUT}/desktop-cookies" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${DESKTOP_URL}/api/settings")" = 204 ]
}

# Files are served by the user's own agent: the home folder is listed, and
# root's is not theirs to see
desktop_files() {
    local home
    home=$(curl -sk --max-time 20 -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/files" | jq -r .home)
    [ "${home}" = "/home/${LOGIN_USER}" ] &&
        [ "$(desktop_code "${DESKTOP_URL}" -b "${OUT}/desktop-cookies" "${DESKTOP_URL}/api/files?path=/root")" = 403 ]
}

# No shell started for a terminal is left running once its window is closed
desktop_terminals_closed() { [ -z "$(ssh_run "systemctl list-units --no-legend 'terminal-*'")" ]; }

# signin.png and desktop.png through a real browser (Playwright's Chromium),
# then a terminal (its shell must be the login user's), the containers and
# the journal: terminal.png, containers.png, console.png
desktop_screens() {
    (cd "${DESKTOP_WEB}" &&
        KURA_DEVICE_URL="${DESKTOP_URL}" KURA_DEVICE_USER="${LOGIN_USER}" KURA_DEVICE_PASS="${LOGIN_PASS}" \
        KURA_DEVICE_SHOTS="${OUT}" bunx playwright test -c playwright.device.config.ts) > "${OUT}/desktop-screens.log" 2>&1 &&
        [ -s "${OUT}/signin.png" ] && [ -s "${OUT}/desktop.png" ] &&
        [ -s "${OUT}/terminal.png" ] && [ -s "${OUT}/containers.png" ] && [ -s "${OUT}/console.png" ] &&
        [ -s "${OUT}/browser.png" ]
}

# The Browser (ADR-036), left open by the screenshots: the login user's own
# unit runs Chromium as them; its socket is in a folder of theirs alone;
# nothing of it listens on a network port; the X server holds its own
# abstract socket (numbered by their uid). Then it stops when asked.
desktop_browser_private() {
    local unit="browser-${LOGIN_USER}" uid ok=0
    uid=$(ssh_run "id -u") || return 1
    report_facts "$(sudo_run "stat -c '%U %a' /run/${unit} /run/${unit}/vnc.sock" | tr '\n' ' ')"
    if [ "$(ssh_run "systemctl is-active ${unit}" || true)" = active ] &&
        [ "$(sudo_run "stat -c '%U %a' /run/${unit}")" = "${LOGIN_USER} 700" ] &&
        ! sudo_run "ss -ltnupH" | grep -q 'Xtigervnc\|chromium' &&
        sudo_run "ss -xlpH" | grep "@/tmp/.X11-unix/X${uid} " | grep -q Xtigervnc &&
        [ "$(ssh_run "ps -o user= -C chromium | sort -u")" = "${LOGIN_USER}" ]; then
        ok=1
    fi
    sudo_run "systemctl stop ${unit}"
    [ "${ok}" = 1 ] && [ "$(ssh_run "systemctl is-active ${unit}" || true)" != active ]
}
