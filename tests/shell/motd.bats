#!/usr/bin/env bats
# tests/shell/motd.bats — the message after login, laid out as Ubuntu's: a
# welcome line, where to look things up, the system information in two
# columns, then notices (scripts/common/motd.sh). motd/10-status gathers the
# facts on the device.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    export LC_ALL=C.UTF-8
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/motd.sh"
    MOTD_WELCOME="Kura 0.4.2 (Debian GNU/Linux 13, kernel 6.12.107+deb13-amd64 x86_64)"
    MOTD_DATE="Tue Nov 10 17:02:31 UTC 2026"
    MOTD_LEFT=("System load:|0.08" "Usage of /:|5.3% of 58.0GB" "Memory usage:|16%" "Swap usage:|0%")
    MOTD_RIGHT=("Processes:|132" "Users logged in:|1" "IPv4 address for eno1:|10.0.5.52"
                "Containers:|3 running, 1 stopped")
    MOTD_UPDATES="Nov 10 04:30"
    MOTD_FAILED=0
    MOTD_REBOOT=""
}

@test "motd: the welcome line, then where to look things up" {
    run motd_render
    [ "$status" -eq 0 ]
    output_has "Welcome to Kura 0.4.2 (Debian GNU/Linux 13, kernel 6.12.107+deb13-amd64 x86_64)"
    output_has " * Documentation:  https://github.com/cbabil/kura"
    output_has " * Containers:     docker ps"
    output_has " * Logs:           journalctl -u <service>"
}

@test "motd: the system information in two aligned columns" {
    run motd_render
    output_has " System information as of Tue Nov 10 17:02:31 UTC 2026"
    output_has "  System load:  0.08              Processes:             132"
    output_has "  Usage of /:   5.3% of 58.0GB    Users logged in:       1"
    output_has "  Memory usage: 16%               IPv4 address for eno1: 10.0.5.52"
    output_has "  Swap usage:   0%                Containers:            3 running, 1 stopped"
}

@test "motd: a column may be shorter (no swap)" {
    MOTD_LEFT=("System load:|0.08" "Usage of /:|5.3% of 58.0GB" "Memory usage:|16%")
    run motd_render
    [ "$status" -eq 0 ]
    output_has "                                  Containers:            3 running, 1 stopped"
    ! output_has "Swap" || false
}

@test "motd: fits an 80-column terminal, with every notice shown" {
    MOTD_FAILED=12
    MOTD_REBOOT="04:30"
    run motd_render
    local line
    while IFS= read -r line; do
        [ "${#line}" -le 80 ] || { echo "too wide (${#line}): ${line}"; return 1; }
    done <<< "$output"
}

@test "motd: says when security updates last installed themselves, or that they haven't yet" {
    run motd_render
    output_has "Security updates install themselves daily; the last run was Nov 10 04:30."
    MOTD_UPDATES=""
    run motd_render
    output_has "Security updates install themselves daily; they haven't run yet."
}

@test "motd: failed services, with the command that lists them" {
    run motd_render
    ! output_has "failed" || false
    MOTD_FAILED=1
    run motd_render
    output_has "1 service has failed: systemctl --failed"
    MOTD_FAILED=3
    run motd_render
    output_has "3 services have failed: systemctl --failed"
}

@test "motd: a pending restart, and when it happens by itself" {
    run motd_render
    ! output_has "restart" || false
    MOTD_REBOOT="04:30"
    run motd_render
    output_has "*** System restart required *** (it restarts by itself at 04:30)"
}

@test "motd: plain text, no colours" {
    MOTD_FAILED=1
    MOTD_REBOOT="04:30"
    run motd_render
    [[ "$output" != *$'\e'* ]]
}

# ---- facts ----

@test "motd_gb: bytes as gigabytes with one decimal" {
    [ "$(motd_gb 1288490188)" = "1.2" ]
    [ "$(motd_gb 0)" = "0.0" ]
}

@test "motd_percent: a share as a whole percent, rounded" {
    [ "$(motd_percent 1 6)" = "17%" ]
    [ "$(motd_percent 0 8)" = "0%" ]
    [ "$(motd_percent 5 0)" = "0%" ]
}

@test "motd_meminfo: memory and swap use from meminfo, swap empty when there is none" {
    local f="${BATS_TEST_TMPDIR}/meminfo"
    printf 'MemTotal: 8000000 kB\nMemAvailable: 6000000 kB\nSwapTotal: 1000000 kB\nSwapFree: 750000 kB\n' > "${f}"
    [ "$(motd_meminfo "${f}")" = "25% 25%" ]
    printf 'MemTotal: 8000000 kB\nMemAvailable: 6000000 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "${f}"
    [ "$(motd_meminfo "${f}")" = "25% " ]
}

# ---- wiring ----

@test "the image installs the MOTD and drops the old banner, status and commands" {
    local custom="${REPO_ROOT}/scripts/common/customize-rootfs.sh"
    file_has "${custom}" "for script in 05-ssh-banner 10-status; do"
    file_has "${custom}" "motd.sh"
    for old in 10-banner 40-status 80-commands; do
        [ ! -e "${REPO_ROOT}/scripts/common/motd/${old}" ]
    done
}

@test "10-status renders the MOTD from motd.sh with the device's facts" {
    local status="${REPO_ROOT}/scripts/common/motd/10-status"
    file_has "${status}" "motd_render"
    file_has "${status}" "LC_ALL=C.UTF-8"
    shellcheck -x "${status}"
}
