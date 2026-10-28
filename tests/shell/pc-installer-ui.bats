#!/usr/bin/env bats
# tests/shell/pc-installer-ui.bats — the PC installer's screen (ui.sh): the
# console palette, the KURA logo, the step list, bands and bars, drawn with
# console-safe characters only.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
ESC=$'\033'

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/pc-installer/ui.sh"
}

# plain: the output without colour escapes
plain() { sed -e $'s/\033\\[[0-9;?]*[A-Za-z]//g' -e $'s/\033\\]P[0-9A-F]\\{7\\}//g' -e $'s/\033[78]//g' <<< "$output"; }

@test "ui_palette: the login screen's colours plus the installer's green, amber, red, panel and band" {
    run ui_palette
    [ "$status" -eq 0 ]
    for entry in 00f172a 7e2e8f0 59146ff Da970ff 894a3b8 9334155 223ce6b 3f59e0b 1ef4444 41e293b E2a1f55 Fffffff; do
        output_has "${ESC}]P${entry}"
    done
}

@test "ui_header: the KURA logo, light to brand purple, with THE STOREHOUSE and the installer's purpose" {
    run ui_header
    [ "$status" -eq 0 ]
    output_has "${ESC}[0;95m██   ██ ██    ██ ██████   █████"
    output_has "${ESC}[0;35m█████   ██    ██ ██████  ███████"
    output_has "T H E   S T O R E H O U S E"
    output_has "Installer"
    output_has "puts Kura on this PC's internal drive"
    output_has "────────"
}

@test "ui_steps: done steps green with details, the current one purple, the rest grey without details" {
    run ui_steps 3 "KURA-INST on sda" "eth0 · 10.0.5.52" "Kura 0.4.1 · 375 MB download" "nvme0n1" "" "user"
    [ "$status" -eq 0 ]
    output_has "${ESC}[0;32m√  ${ESC}[0;37mUSB key"
    output_has "KURA-INST on sda"
    output_has "${ESC}[0;95m›  ${ESC}[0;97mRelease"
    output_has "Kura 0.4.1 · 375 MB download"
    output_has "${ESC}[0;91m·  ${ESC}[0;90mInternal drive"
    ! output_has "nvme0n1" || false
    [ "$(plain | grep -c .)" -eq 6 ]
}

@test "ui_steps: past the last step everything is done and every detail shows" {
    run ui_steps 7 a b c d "" f
    [ "$(plain | grep -c '√')" -eq 6 ]
    output_has "f"
    ! output_has "›" || false
}

@test "ui_bar: filled and empty cells in proportion, never more than the width" {
    run ui_bar 7 10 40
    [ "$(plain | grep -o '█' | wc -l)" -eq 28 ]
    [ "$(plain | grep -o '░' | wc -l)" -eq 12 ]
    run ui_bar 12 10 10
    [ "$(plain | grep -o '█' | wc -l)" -eq 10 ]
    run ui_bar 0 0 10
    [ "$(plain | grep -o '░' | wc -l)" -eq 10 ]
}

@test "ui_warning, ui_done and ui_error: amber, green and red bands" {
    run ui_warning "Everything will be erased."
    output_has "${ESC}[0;33;44m  ▲  Everything will be erased."
    run ui_done "Kura is installed on nvme0n1."
    output_has "${ESC}[0;30;42m  √  Kura is installed on nvme0n1."
    run ui_error "No network."
    output_has "${ESC}[0;31m"
    output_has "No network."
}

@test "ui_clear: back to the background colour, screen cleared, cursor home" {
    run ui_clear
    output_has "${ESC}[2J${ESC}[H"
}

@test "ui.sh: console-safe characters only (no CJK, no emoji)" {
    # perl decodes UTF-8 itself, so this holds in any locale (CI has no en_US)
    [ -z "$(perl -CS -Mutf8 -ne 'print for /[^\x00-\x7F█░─√›▲·]/g' < "${REPO_ROOT}/scripts/pc-installer/ui.sh")" ]
}

# ---- In the initrd ----

@test "build-initrd: copies the screen scripts and Terminus 16x32, uncompressed for setfont" {
    local build="${REPO_ROOT}/scripts/pc-installer/build-initrd.sh"
    for file in install.sh run.sh screen.sh ui.sh; do
        grep -q "\${SCRIPT_DIR}/${file}" "${build}"
    done
    file_has "${build}" "/usr/share/consolefonts/Uni3-Terminus32x16.psf.gz"
    file_has "${build}" '/font.psf"'
    grep -qx "console-setup-linux" "${REPO_ROOT}/config/packages-pc-installer.list"
}

@test "build-initrd: setfont comes from kbd (Debian's static busybox has none)" {
    grep -qx kbd "${REPO_ROOT}/config/packages-pc-installer.list"
    grep "^TOOLS=" "${REPO_ROOT}/scripts/pc-installer/build-initrd.sh" | grep -q "/usr/bin/setfont"
    ! grep -A2 "^for applet in" "${REPO_ROOT}/scripts/pc-installer/build-initrd.sh" | grep -qw setfont
}

@test "init: loads the font, then draws through ui.sh before looking for the key" {
    local init="${REPO_ROOT}/scripts/pc-installer/init"
    file_has "${init}" 'setfont -C /dev/tty1 "${INSTALLER_COMMON}/font.psf"'
    file_has "${init}" 'source "${INSTALLER_COMMON}/ui.sh"'
    [ "$(grep -n 'setfont' "${init}" | cut -d: -f1)" -lt "$(grep -n '^ui_palette' "${init}" | cut -d: -f1)" ]
    [ "$(grep -n '^ui_header' "${init}" | cut -d: -f1)" -lt "$(grep -n 'findfs' "${init}" | cut -d: -f1)" ]
    ! grep -q '^ *echo "[A-Z]' "${init}" || false
}
