#!/usr/bin/env bats
# tests/shell/branding.bats — what a Kura device shows (ADR-018): the boot
# splash on the PC image (Plymouth theme "kura": 蔵, the kicker, the
# wordmark and the tagline of the README banner) and the console login
# screen (/etc/issue) on every image.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
THEME="${REPO_ROOT}/overlay/x86_64/usr/share/plymouth/themes/kura"
TAGLINE="The lightweight OS for your home server."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/issue.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/x86_64/pc-image.sh"
}

# ---- Login screen ----

@test "kura_issue: the console takes the banner's colours, then the screen is cleared" {
    run kura_issue "${TAGLINE}"
    [ "$status" -eq 0 ]
    output_has $'\e]P00f172a'   # background: navy
    output_has $'\e]P59146ff'   # purple
    output_has $'\e]PDa970ff'   # light purple
    output_has $'\e]P7e2e8f0'   # text
    output_has $'\e]P894a3b8'   # muted
    output_has $'\e[2J'
}

@test "kura_issue: the purple follows the brand colour (OS_COLOR)" {
    run kura_issue "${TAGLINE}" 00ff88
    output_has $'\e]P500ff88'
}

@test "customize-rootfs: /etc/issue is the new login screen, with OS_ISSUE as the tagline" {
    file_has "${REPO_ROOT}/scripts/common/brand-defaults.sh" "DEFAULT_TAGLINE=\"${TAGLINE}\""
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'TAGLINE="${OS_ISSUE:-${DEFAULT_TAGLINE}}"'
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'kura_issue "${TAGLINE}"'
    file_has "${REPO_ROOT}/.env.example" "OS_ISSUE=\"${TAGLINE}\""
}

@test "the old-brand overlay issue and motd files are gone" {
    for f in overlay/rpi5/etc/issue overlay/rpi5/etc/motd overlay/x86_64/etc/issue overlay/x86_64/etc/motd; do
        [ ! -e "${REPO_ROOT}/${f}" ]
    done
}

# ---- Boot splash (PC image) ----

@test "pc_grub_cfg: quiet boot into the splash, serial consoles left to the text log" {
    run pc_grub_cfg 1111-uuid 2222-partuuid Kura
    output_has "ro quiet splash plymouth.ignore-serial-consoles loglevel=3 console="
    # the console keeps its cursor for the login and the shell
    ! output_has "vt.global_cursor_default"
}

@test "plymouth theme kura: script theme with its artwork" {
    file_has "${THEME}/kura.plymouth" "ModuleName=script"
    file_has "${THEME}/kura.plymouth" "ImageDir=/usr/share/plymouth/themes/kura"
    file_has "${THEME}/kura.plymouth" "ScriptFile=/usr/share/plymouth/themes/kura/kura.script"
    for image in logo.png dot.png; do
        [ -s "${THEME}/${image}" ]
        file_has "${THEME}/kura.script" "\"${image}\""
    done
}

@test "plymouth: installed on the PC image only, with the fontconfig its initrd hook copies" {
    grep -qx plymouth "${REPO_ROOT}/config/packages-x86_64.list"
    grep -qx fontconfig "${REPO_ROOT}/config/packages-x86_64.list"
    ! grep -qx plymouth "${REPO_ROOT}/config/packages-common.list"
}

@test "plymouthd.conf: kura is the default splash theme" {
    file_has "${REPO_ROOT}/overlay/x86_64/etc/plymouth/plymouthd.conf" "Theme=kura"
}

@test "build.sh: the PC image's initrd is rebuilt after the theme is in place" {
    file_has "${REPO_ROOT}/build.sh" "refresh_initramfs"
}

# ---- SSH welcome ----

@test "ssh banner: 蔵, the kicker and the tagline from brand.env, in a purple gradient" {
    local banner="${REPO_ROOT}/scripts/common/motd/05-ssh-banner"
    file_has "${banner}" "蔵 · THE STOREHOUSE"
    file_has "${banner}" 'BRAND_TAGLINE'
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'BRAND_TAGLINE='
    ! grep -q "Welcome to" "${banner}"
}
