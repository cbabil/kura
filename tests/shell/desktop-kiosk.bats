#!/usr/bin/env bats
# tests/shell/desktop-kiosk.bats — the local screen (ADR-033): opt-in at
# build (OS_KIOSK), PC only, and nothing on a machine without a display.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SRC="${REPO_ROOT}/packages/os-desktop/src"

setup() {
    load test_helper
    desktop_rootfs
    DRM="${BATS_TEST_TMPDIR}/drm"
    mkdir -p "${DRM}"
    KIOSK=$(branded kiosk)
    UNIT="${ROOTFS}/usr/lib/systemd/system/kura-kiosk.service"
    WANTED="${ROOTFS}/etc/systemd/system/multi-user.target.wants/kura-kiosk.service"
}

connector() { mkdir -p "${DRM}/$1" && echo "$2" > "${DRM}/$1/status"; }

@test "the Pi's image has nothing of the local screen" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ ! -e "${UNIT}" ]
    [ ! -e "${ROOTFS}/usr/lib/kura/kura-kiosk" ]
    [ ! -e "${ROOTFS}/usr/lib/sysusers.d/kura-kiosk.conf" ]
    # build.sh sets both switches for the PC image alone
    # shellcheck disable=SC2016
    grep -qF '[ "${ARCH}" != "amd64" ] || { kiosk="${OS_KIOSK:-false}"; kiosk_files="true"; }' "${REPO_ROOT}/build.sh"
}

@test "every PC image has the unit, its user and its command, turned off" {
    OS_KIOSK_FILES=true run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ -x "${ROOTFS}/usr/lib/kura/kura-kiosk" ]
    [ -f "${UNIT}" ]
    [ ! -e "${WANTED}" ]
    file_has "${ROOTFS}/usr/lib/sysusers.d/kura-kiosk.conf" "u kura-kiosk - "
    grep -q '^OS_KIOSK="false"' "${REPO_ROOT}/.env.example"
    run grep -rl "__BRAND" "${UNIT}" "${ROOTFS}/usr/lib/kura/kura-kiosk" "${ROOTFS}/usr/lib/sysusers.d/kura-kiosk.conf"
    [ -z "$output" ]
}

@test "OS_KIOSK turns it on" {
    OS_KIOSK_FILES=true OS_KIOSK=true run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ -L "${WANTED}" ]
}

@test "the kura package owns the screen's files, so an upgrade keeps them" {
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    OS_KIOSK_FILES=true "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    run kura_owned "${ROOTFS}" kura
    [[ "$output" == *"usr/lib/kura/kura-kiosk"* ]]
    [[ "$output" == *"usr/lib/systemd/system/kura-kiosk.service"* ]]
    [[ "$output" == *"usr/lib/sysusers.d/kura-kiosk.conf"* ]]
}

@test "the unit: its own user without groups, a session, no rights, and it comes back" {
    OS_KIOSK_FILES=true "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    local line
    for line in "User=kura-kiosk" "PAMName=login" "TTYPath=/dev/tty7" "ConditionPathExists=/usr/bin/cage" \
                "ExecCondition=/usr/lib/kura/kura-kiosk display" "ExecStart=/usr/lib/kura/kura-kiosk run" \
                "Restart=always" "NoNewPrivileges=yes" "ProtectSystem=full" "InaccessiblePaths=-/home -/root" \
                "Environment=HOME=/run/kura-kiosk"; do
        grep -qxF "${line}" "${UNIT}" || { echo "missing: ${line}"; return 1; }
    done
    # ProtectHome would hide /run/user, where the session's socket is
    run grep -E "^(ProtectHome|ProtectSystem=strict|Wants=.*desktopd)" "${UNIT}"
    [ "$status" -ne 0 ]
    run grep -E "^m " "${ROOTFS}/usr/lib/sysusers.d/kura-kiosk.conf"
    [ "$status" -ne 0 ]
}

@test "the build adds the screen's packages to a PC image built with OS_KIOSK only" {
    # shellcheck disable=SC2016
    grep -qF 'if [ "${OS_KIOSK:-false}" = "true" ] && [ "${TARGET}" = "x86_64" ]; then' "${REPO_ROOT}/build.sh"
    file_has "${REPO_ROOT}/build.sh" 'packages-kiosk.list'
    grep -qx "cage" "${REPO_ROOT}/config/packages-kiosk.list"
    grep -qx "cog" "${REPO_ROOT}/config/packages-kiosk.list"
    run grep -E "^(cage|cog)$" "${REPO_ROOT}/config/packages-common.list" "${REPO_ROOT}/config/packages-rpi5.list" "${REPO_ROOT}/config/packages-x86_64.list"
    [ "$status" -ne 0 ]
}

@test "display: only a connected screen counts" {
    KIOSK_DRM="${DRM}" run "${KIOSK}" display
    [ "$status" -ne 0 ]
    connector card0-HDMI-A-1 disconnected
    connector card0-DP-1 unknown
    mkdir -p "${DRM}/card0" "${DRM}/version"
    KIOSK_DRM="${DRM}" run "${KIOSK}" display
    [ "$status" -ne 0 ]
    connector card1-eDP-1 connected
    KIOSK_DRM="${DRM}" run "${KIOSK}" display
    [ "$status" -eq 0 ]
}

@test "run: the browser fills the screen with this server's own desktop, and nothing else is a command" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/sh\necho "cage $*"\n' > "${BATS_TEST_TMPDIR}/bin/cage"
    chmod +x "${BATS_TEST_TMPDIR}/bin/cage"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" run "${KIOSK}" run
    [ "$output" = "cage -s -- cog --platform=wl --ignore-tls-errors https://localhost/" ]
    run "${KIOSK}" https://example.org
    [ "$status" -eq 2 ]
    run "${KIOSK}"
    [ "$status" -eq 2 ]
}
