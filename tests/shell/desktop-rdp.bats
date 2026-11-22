#!/usr/bin/env bats
# tests/shell/desktop-rdp.bats — Remote Desktop (ADR-035): Debian's xrdp,
# whose session is one browser on Kura Desktop. PC only, off until Settings
# turns it on. The login and the sessions are xrdp's own; Kura adds the
# session's program, the list of who may connect, and the switch.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    desktop_rootfs
    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${BIN}"
    SESSION=$(branded rdp-session)
    DROPIN="${ROOTFS}/usr/lib/systemd/system/xrdp.service.d/10-kura.conf"
    WANTS="${ROOTFS}/etc/systemd/system/multi-user.target.wants"
}

install_pc() { OS_KIOSK_FILES=true "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"; }

@test "the Pi's image has nothing of Remote Desktop" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ -z "$(find "${ROOTFS}" -name '*rdp*')" ]
}

@test "every PC image has the session's program and xrdp's list of who may connect" {
    install_pc
    [ -x "${ROOTFS}/usr/lib/kura/kura-rdp-session" ]
    [ -f "${DROPIN}" ]
    [ -f "${ROOTFS}/usr/lib/kura/kura-settings-screens" ]
    run grep -rl "__BRAND" "${DROPIN}" "${ROOTFS}/usr/lib/kura/kura-rdp-session" "${ROOTFS}/usr/lib/kura/kura-settings-screens"
    [ -z "$output" ]
    # no user of its own: a session is the person's who signed in
    [ "$(grep -c "^u " "${ROOTFS}/usr/lib/sysusers.d/kura-kiosk.conf")" -eq 1 ]
}

# apt turns a service on when it installs it; Remote Desktop opens a port,
# so only Settings may
@test "no build leaves xrdp on" {
    mkdir -p "${WANTS}"
    ln -s /usr/lib/systemd/system/xrdp.service "${WANTS}/xrdp.service"
    ln -s /usr/lib/systemd/system/xrdp-sesman.service "${WANTS}/xrdp-sesman.service"
    ln -s /usr/lib/systemd/system/ssh.service "${WANTS}/ssh.service"
    OS_KIOSK=true install_pc
    [ ! -L "${WANTS}/xrdp.service" ]
    [ ! -L "${WANTS}/xrdp-sesman.service" ]
    [ -L "${WANTS}/ssh.service" ]
}

@test "the kura package owns its files, so an upgrade keeps them" {
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    install_pc
    run kura_owned "${ROOTFS}" kura
    output_has "usr/lib/kura/kura-rdp-session"
    output_has "usr/lib/kura/kura-settings-screens"
    output_has "usr/lib/systemd/system/xrdp.service.d/10-kura.conf"
}

@test "who may connect: this machine and the local networks, as the firewall has them" {
    install_pc
    grep -qxF "[Service]" "${DROPIN}"
    grep -qxF "IPAddressDeny=any" "${DROPIN}"
    source "${REPO_ROOT}/packages/os-security/src/lib/firewall.sh"
    grep -qxF "IPAddressAllow=localhost ${DESKTOP_NETS_4}" "${DROPIN}"
}

@test "the build adds xrdp, an X server and a browser for it to the screen's packages only" {
    local package
    for package in xrdp xorgxrdp xserver-xorg-core x11-common surf matchbox-window-manager; do
        grep -qx "${package}" "${REPO_ROOT}/config/packages-kiosk.list"
        run grep -x "${package}" "${REPO_ROOT}/config/packages-common.list" "${REPO_ROOT}/config/packages-rpi5.list" "${REPO_ROOT}/config/packages-x86_64.list"
        [ "$status" -ne 0 ]
    done
}

@test "the session: a window manager that fills the screen, then one browser on this server's own desktop" {
    printf '#!/bin/sh\necho "surf $*"\n' > "${BIN}/surf"
    printf '#!/bin/sh\necho "matchbox $*" >> "%s"\n' "${BATS_TEST_TMPDIR}/wm" > "${BIN}/matchbox-window-manager"
    chmod +x "${BIN}/surf" "${BIN}/matchbox-window-manager"
    PATH="${BIN}:${PATH}" run "${SESSION}"
    [ "$status" -eq 0 ]
    [ "$output" = "surf -F -K -t https://localhost/" ]
    [ "$(cat "${BATS_TEST_TMPDIR}/wm")" = "matchbox -use_titlebar no" ]
    # whatever it is given, it opens nothing else
    PATH="${BIN}:${PATH}" run "${SESSION}" https://example.org
    [ "$output" = "surf -F -K -t https://localhost/" ]
}
