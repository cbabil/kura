#!/usr/bin/env bats
# tests/shell/pc-installer-screen.bats — what install.sh shows on its screen:
# the details beside each step, the countdown bar and the write progress
# read from /sys/block/<dev>/stat.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
ESC=$'\033'
GB=1000000000

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/pc-installer/install.sh"
    SYS_BLOCK="${BATS_TEST_TMPDIR}/sys/block"
    KEY_DIR="${BATS_TEST_TMPDIR}/key"
    mkdir -p "${SYS_BLOCK}/nvme0n1" "${KEY_DIR}"
}

# fake_stat <sectors-written>: /sys/block/nvme0n1/stat, 7th field written
fake_stat() {
    echo "  120  0  9000  40  300  12  $1  900  0  500  940" > "${SYS_BLOCK}/nvme0n1/stat"
}

plain() { sed -e $'s/\033\\[[0-9;?]*[A-Za-z]//g' -e $'s/\033[78]//g' <<< "$output"; }

@test "net_info: the first global IPv4 address and its interface" {
    ip() { echo "2: eth0    inet 10.0.5.52/24 brd 10.0.5.255 scope global dynamic eth0\\       valid_lft 86000sec"; }
    run net_info
    [ "$output" = "eth0 · 10.0.5.52" ]
    ip() { return 1; }
    run net_info
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "release_info: the version and download size from the manifest" {
    echo '{"version":"v0.4.1","bundles":{"x86_64":{"size":375123456}}}' > "${BATS_TEST_TMPDIR}/m.json"
    run release_info "${BATS_TEST_TMPDIR}/m.json"
    [ "$output" = "Kura 0.4.1 · 375 MB download" ]
}

@test "setup_info and setup_login: what the setup file hands over, and how to log in" {
    run setup_info
    [ "$output" = "no setup file on the key" ]
    echo '{"version":1,"hostname":"den","user":{"name":"ana"},"ssh":{"authorizedKeys":["k"]},
        "wifi":{"ssid":"Home"}}' > "${KEY_DIR}/kura-setup.json"
    run setup_info
    [ "$output" = "user ana, SSH key, hostname den, Wi-Fi" ]
    # only the user name: Kura has no .local name; its login screen shows the address
    run setup_login
    [ "$output" = "ana" ]
}

@test "finished: points to Kura's login screen for the address, never a .local name" {
    ui_color() { :; }; show() { :; }; ui_done() { echo "$*"; }
    run finished vda ana
    output_has "Log in as ana with SSH: Kura's login screen shows the address and the command."
    ! output_has ".local"
    run finished vda ""
    output_has "Kura's login screen shows the address and the SSH command."
}

@test "written_bytes: sectors written times 512, 0 without a stat file" {
    fake_stat 2048
    run written_bytes nvme0n1
    [ "$output" -eq 1048576 ]
    run written_bytes sdz
    [ "$output" -eq 0 ]
}

@test "progress_lines: bar, percent, GB written of the image, MB/s and time left" {
    run progress_lines 2100000000 3500000000 55
    [ "$status" -eq 0 ]
    output_has "60%"
    output_has "2.1 GB of 3.5 GB written · 38 MB/s · about 36 s left"
    [ "$(plain | grep -o '█' | wc -l)" -eq 45 ]
}

@test "progress_lines: no rate before the first bytes, minutes for long waits" {
    run progress_lines 0 3500000000 0
    output_has "0.0 GB of 3.5 GB written"
    ! output_has "MB/s" || false
    run progress_lines $(( 2 * GB )) $(( 4 * GB )) 400
    output_has "5 MB/s · about 6 min left"
}

@test "watch_progress: redraws the progress from the drive's counters every second" {
    fake_stat 0
    watch_progress nvme0n1 $(( 1048576 * 4 )) > "${BATS_TEST_TMPDIR}/screen" &
    local pid=$!
    sleep 0.3
    fake_stat 4096
    sleep 1.2
    kill "${pid}"
    file_has "${BATS_TEST_TMPDIR}/screen" "0%"
    file_has "${BATS_TEST_TMPDIR}/screen" "50%"
    file_has "${BATS_TEST_TMPDIR}/screen" "${ESC}8"
}

@test "countdown: a shrinking bar under the seconds left" {
    run countdown 2 < /dev/null
    [ "$status" -eq 0 ]
    output_has "Installing in "
    output_has "Press any key to cancel. Nothing has been written yet."
    [ "$(plain | grep 'Installing in' | head -1 | grep -o '█' | wc -l)" -eq 40 ]
    [ "$(plain | grep 'Installing in' | sed -n 2p | grep -o '█' | wc -l)" -eq 20 ]
}
