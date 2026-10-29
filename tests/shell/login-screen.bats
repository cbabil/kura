#!/usr/bin/env bats
# tests/shell/login-screen.bats — the console login screen, layout B
# (ADR-019): the big KURA logo, kicker and tagline on the left, a panel on the
# right with host, address, how to connect, system, uptime and disk, the
# services and the outcome of the imager's setup. kura-issue renders it at
# boot and every minute; agetty fills host, address and date.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
TAGLINE="The lightweight OS for your home server."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/issue.sh"
    LOGIN_USER="chris"
    LOGIN_VERSION="Kura 0.4.2"
    LOGIN_UPTIME="3 min · disk 3% used"
    LOGIN_SERVICES="docker:active ssh:active network:active"
    LOGIN_SETUP="applied"
    LOGIN_COLS=120
}


@test "layout B: logo and the panel on the same lines when the console is wide" {
    run kura_issue
    [ "$status" -eq 0 ]
    matches "$output" "*██   ██ ██    ██ ██████   █████*┌──*"
    output_has "T H E   S T O R E H O U S E"
    output_has "The lightweight OS"
    output_has "for your home server."
}

@test "layout B: host, address and date filled in by agetty, connect with the login user" {
    run kura_issue
    output_has '\n'
    output_has '\4'
    output_has 'ssh chris@\4'
    output_has '\d · \t'
    output_has 'Kura 0.4.2 · \S{PRETTY_NAME} · \m'
    output_has "3 min · disk 3% used"
}

@test "services: a green dot when running, red when not" {
    LOGIN_SERVICES="docker:active ssh:failed"
    run kura_issue
    output_has "${ISSUE_GREEN}•${ISSUE_TEXT} docker"
    output_has "${ISSUE_RED}•${ISSUE_TEXT} ssh"
}

@test "setup: says it was applied, or why it was ignored" {
    run kura_issue
    output_has "${ISSUE_GREEN}•${ISSUE_TEXT} setup applied"
    LOGIN_SETUP="ignored: invalid user name (taken by a system account or group)"
    run kura_issue
    output_has "${ISSUE_AMBER}▲ setup ignored"
    output_has "${ISSUE_AMBER}invalid user name (taken by a system account or group)"
    LOGIN_SETUP=""
    run kura_issue
    ! output_has "setup"
}

@test "narrow console: the panel goes under the logo" {
    LOGIN_COLS=80
    run kura_issue
    ! matches "$output" "*█████*┌──*"
    output_has "┌──"
}

@test "only characters the console font can draw" {
    LOGIN_SETUP="ignored: x"
    run kura_issue
    [ -z "$(printf '%s' "$output" | perl -CS -ne 'print for /[^\x00-\x7F\x{2588}\x{2500}\x{2502}\x{250C}\x{2514}\x{00B7}\x{2022}\x{25B2}]/g')" ]
}

@test "without runtime facts (build time): agetty's own system line, no services" {
    unset LOGIN_VERSION LOGIN_UPTIME LOGIN_SERVICES LOGIN_SETUP LOGIN_USER
    run kura_issue
    output_has '\S{PRETTY_NAME} · \m'
    output_has 'ssh <user>@\4'
    ! output_has "•"
}

# ---- kura-issue: gathers the facts at runtime ----

kura_issue_env() {
    local dir="${BATS_TEST_TMPDIR}"
    printf 'BRAND_NAME="Kura"\nBRAND_VERSION="0.4.2"\nBRAND_COLOR="#9146FF"\n' > "${dir}/brand.env"
    printf 'BRAND_TAGLINE=%q\n' "${TAGLINE}" >> "${dir}/brand.env"
    printf '200.5 100.0\n' > "${dir}/uptime"
    printf 'chris:x:1000:1000::/home/chris:/bin/bash\n' > "${dir}/passwd"
    export KURA_BRAND_ENV="${dir}/brand.env"
    export KURA_UPTIME="${dir}/uptime" KURA_PASSWD="${dir}/passwd"
    export KURA_SETUP_STATUS="${dir}/setup-status" KURA_ISSUE="${dir}/issue"
    export LOGIN_COLS=120
    # one call for every service, one state per line in order
    systemctl() { printf 'active\ninactive\nactive\n'; }
    timeout() { shift; "$@"; }
    df() { printf 'Use%%\n 3%%\n'; }
    agetty() { echo "agetty $*" >> "${BATS_TEST_TMPDIR}/calls"; }
    export -f systemctl timeout df agetty
}

@test "kura-issue: writes the screen with this device's facts, then redraws waiting prompts" {
    kura_issue_env
    echo "applied" > "${KURA_SETUP_STATUS}"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    [ "$status" -eq 0 ]
    file_has "${KURA_ISSUE}" 'Kura 0.4.2 · \S{PRETTY_NAME} · \m'
    file_has "${KURA_ISSUE}" "3 min · disk 3% used"
    # the stubbed systemctl reports ssh inactive: a red dot
    file_has "${KURA_ISSUE}" "${ISSUE_RED}•${ISSUE_TEXT} ssh"
    file_has "${KURA_ISSUE}" 'ssh chris@\4'
    file_has "${KURA_ISSUE}" "setup applied"
    file_has "${BATS_TEST_TMPDIR}/calls" "agetty --reload"
}

@test "one-time password: shown on the screen with what to do" {
    LOGIN_PASSWORD="abcd-efgh-jkmn"
    run kura_issue
    output_has "Password"
    output_has "abcd-efgh-jkmn"
    output_has "one-time"
}

@test "kura-issue: shows the one-time password until the owner has changed it" {
    kura_issue_env
    echo "abcd-efgh-jkmn" > "${BATS_TEST_TMPDIR}/otp"
    printf 'chris:$y$x:0:0:99999:7:::\n' > "${BATS_TEST_TMPDIR}/shadow"
    export KURA_ONE_TIME_PASSWORD="${BATS_TEST_TMPDIR}/otp" KURA_SHADOW="${BATS_TEST_TMPDIR}/shadow"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    file_has "${KURA_ISSUE}" "abcd-efgh-jkmn"
    # changed at first login: the last-change day is no longer 0
    printf 'chris:$y$new:20400:0:99999:7:::\n' > "${BATS_TEST_TMPDIR}/shadow"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    ! file_has "${KURA_ISSUE}" "abcd-efgh-jkmn"
    [ ! -e "${BATS_TEST_TMPDIR}/otp" ]
}

@test "kura-issue: an ignored setup shows its reason" {
    kura_issue_env
    echo "ignored: invalid user name (taken by a system account or group)" > "${KURA_SETUP_STATUS}"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    file_has "${KURA_ISSUE}" "setup ignored"
    file_has "${KURA_ISSUE}" "invalid user name (taken by a system account or group)"
}

@test "kura-issue: an unchanged screen is not rewritten, and nothing is redrawn" {
    kura_issue_env
    run "${REPO_ROOT}/scripts/common/kura-issue"
    rm -f "${BATS_TEST_TMPDIR}/calls"
    touch -t 202001010000 "${KURA_ISSUE}"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    [ "$status" -eq 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/calls" ]
    [ -z "$(find "${KURA_ISSUE}" -newermt 2021-01-01)" ]
}

@test "kura-issue: uptime in minutes for the first hour, then hours, then days" {
    kura_issue_env
    printf '7300.2 0\n' > "${KURA_UPTIME}"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    file_has "${KURA_ISSUE}" "2 h · disk"
    printf '200000 0\n' > "${KURA_UPTIME}"
    run "${REPO_ROOT}/scripts/common/kura-issue"
    file_has "${KURA_ISSUE}" "2 days · disk"
}

# ---- installed in the image ----

@test "install_login_screen: script, unit and minute timer installed and enabled" {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/install-firstboot.sh"
    local rootfs="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${rootfs}"
    install_login_screen "${rootfs}" kura Kura "${REPO_ROOT}/scripts/common"
    [ -x "${rootfs}/usr/lib/kura/kura-issue" ]
    [ -f "${rootfs}/usr/lib/kura/issue.sh" ]
    file_has "${rootfs}/usr/lib/systemd/system/kura-issue.service" "ExecStart=/usr/lib/kura/kura-issue"
    # never behind a first boot that keeps retrying, never ahead of the prompt
    ! grep -q "kura-firstboot" "${rootfs}/usr/lib/systemd/system/kura-issue.service"
    ! grep -q "Before=getty" "${rootfs}/usr/lib/systemd/system/kura-issue.service"
    file_has "${rootfs}/usr/lib/systemd/system/kura-issue.service" "LogLevelMax=notice"
    file_has "${rootfs}/usr/lib/systemd/system/kura-issue.timer" "OnUnitActiveSec=1min"
    [ -L "${rootfs}/etc/systemd/system/multi-user.target.wants/kura-issue.service" ]
    [ -L "${rootfs}/etc/systemd/system/timers.target.wants/kura-issue.timer" ]
}

@test "console font: Terminus 16x32 Uni3 (has the bullet and triangle), as the screen was designed" {
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'FONTFACE="Terminus"'
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'FONTSIZE="16x32"'
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'CODESET="Uni3"'
}

@test "console font: the package's cached setup is dropped, so the first boot applies Terminus" {
    # console-setup reuses /etc/console-setup/cached_* made at install, with the
    # default font, and would ignore /etc/default/console-setup
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'rm -f "${ROOTFS}"/etc/console-setup/cached_*'
}

@test "with no user name (the image's own screen), the connect line says <user>" {
    LOGIN_USER=""
    run kura_issue
    output_has 'ssh <user>@\4'
}

@test "layout B: the panel's edge is in the same column on every line, and nothing passes 120 columns" {
    LOGIN_SETUP="ignored: invalid user name (taken by a system account or group)"
    run kura_issue
    # printed lines without colour escapes, measured in characters
    local plain
    plain=$(printf '%s\n' "$output" | sed $'s/\033\\[[0-9;]*m//g; s/\033\\][P][0-9A-F][0-9a-f]\\{6\\}//g')
    [ "$(printf '%s\n' "${plain}" | perl -CS -Mutf8 -ne 'print index($_, "│"), "\n" if /│/' | sort -u | wc -l | tr -d ' ')" = 1 ]
    [ "$(printf '%s\n' "${plain}" | perl -CS -ne 'print "$.\n" if length($_) - 1 > 120')" = "" ]
    output_has "▲ setup ignored"
}
