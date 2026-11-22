#!/usr/bin/env bats
# tests/shell/mdns.bats — kura.local (ADR-030): scripts/common/mdns.sh puts
# Kura's avahi settings into the image as files of the kura package, so a
# device that upgrades runs the same settings as a new image.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    source "${REPO_ROOT}/scripts/common/mdns.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    CONF="${ROOTFS}/usr/lib/kura/avahi-daemon.conf"
    DROPIN="${ROOTFS}/usr/lib/systemd/system/avahi-daemon.service.d/10-kura.conf"
    mkdir -p "${ROOTFS}"
}

@test "install_mdns: avahi runs with Kura's settings, Debian's own file left alone" {
    run install_mdns "${ROOTFS}" kura
    [ "$status" -eq 0 ]
    [ -f "${CONF}" ]
    [ ! -e "${ROOTFS}/etc/avahi/avahi-daemon.conf" ]
    grep -qxF "ExecStart=" "${DROPIN}"
    grep -qxF "ExecStart=/usr/sbin/avahi-daemon -s -f /usr/lib/kura/avahi-daemon.conf" "${DROPIN}"
    run grep -c "__BRAND__" "${DROPIN}"
    [ "$output" = "0" ]
}

@test "the settings: IPv4 only, nothing wide-area, nothing about the hardware, limits kept" {
    install_mdns "${ROOTFS}" kura
    local line
    for line in use-ipv4=yes use-ipv6=no deny-interfaces=docker0 enable-wide-area=no publish-hinfo=no \
                publish-workstation=no enable-reflector=no rlimit-core=0 rlimit-nproc=3; do
        grep -qxF "${line}" "${CONF}" || { echo "missing ${line}"; return 1; }
    done
    grep -qx '\[rlimits\]' "${CONF}"
}

@test "the package owns both files, and the image must have them" {
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    install_mdns "${ROOTFS}" kura
    run kura_owned "${ROOTFS}" kura
    [[ "$output" == *"usr/lib/kura/avahi-daemon.conf"* ]]
    [[ "$output" == *"usr/lib/systemd/system/avahi-daemon.service.d/10-kura.conf"* ]]
    file_has "${REPO_ROOT}/scripts/common/verify-rootfs.sh" 'usr/lib/${b}/avahi-daemon.conf'
    file_has "${REPO_ROOT}/scripts/common/verify-rootfs.sh" 'usr/lib/systemd/system/avahi-daemon.service.d/10-${b}.conf'
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'install_mdns "${ROOTFS}"'
    [ ! -e "${REPO_ROOT}/overlay/common/etc/avahi/avahi-daemon.conf" ]
}
