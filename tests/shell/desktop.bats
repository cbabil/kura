#!/usr/bin/env bats
# tests/shell/desktop.bats — Kura Desktop in the image (ADR-023, ADR-024):
# scripts/common/install-desktop.sh and packages/os-desktop/src/os-desktop-cert

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    DIST="${BATS_TEST_TMPDIR}/dist"
    mkdir -p "${ROOTFS}/etc/kura/security" "${DIST}"
    echo '{"network_security": {"firewall_preset": "strict"}}' > "${ROOTFS}/etc/kura/security/hardening.json"
    printf '#!/bin/sh\necho desktopd\n' > "${DIST}/kura-desktopd"
    printf '#!/bin/sh\necho helper\n' > "${DIST}/kura-helper"
    export OS_BRAND=kura OS_NAME=Kura
    INSTALL="${REPO_ROOT}/scripts/common/install-desktop.sh"
    CERT="${REPO_ROOT}/packages/os-desktop/src/os-desktop-cert"
}

units() { echo "${ROOTFS}/usr/lib/systemd/system"; }

# ---- install-desktop.sh ----

@test "install: the two programs go to /usr/lib/kura, executable" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ -x "${ROOTFS}/usr/lib/kura/kura-desktopd" ]
    [ -x "${ROOTFS}/usr/lib/kura/kura-helper" ]
    [ -x "${ROOTFS}/usr/lib/kura/kura-desktop-cert" ]
}

@test "install: units, D-Bus policy, user and state folder, branded" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    for unit in kura-desktopd kura-helper kura-desktop-cert; do
        [ -f "$(units)/${unit}.service" ]
    done
    file_has "${ROOTFS}/usr/share/dbus-1/system.d/io.kura.Helper.conf" '<policy user="kura-desktop">'
    file_has "${ROOTFS}/usr/lib/sysusers.d/kura-desktop.conf" "u kura-desktop"
    file_has "${ROOTFS}/usr/lib/tmpfiles.d/kura-desktop.conf" "/var/lib/kura/desktop"
    run grep -rl "__BRAND" "$(units)" "${ROOTFS}/usr/share/dbus-1" "${ROOTFS}/usr/lib/sysusers.d" \
        "${ROOTFS}/usr/lib/tmpfiles.d" "${ROOTFS}/usr/lib/kura"
    [ "$status" -ne 0 ]
}

@test "install: the units start at boot" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    for unit in kura-desktopd kura-helper kura-desktop-cert; do
        [ "$(readlink "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${unit}.service")" = \
          "/usr/lib/systemd/system/${unit}.service" ]
    done
}

@test "install: tells the firewall to open the desktop's port" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.network_security.desktop' "${ROOTFS}/etc/kura/security/hardening.json")" = "true" ]
    [ "$(jq -r '.network_security.firewall_preset' "${ROOTFS}/etc/kura/security/hardening.json")" = "strict" ]
}

@test "install: the server runs unprivileged, with only the right to bind 443" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    local d; d="$(units)/kura-desktopd.service"
    file_has "${d}" "User=kura-desktop"
    file_has "${d}" "AmbientCapabilities=CAP_NET_BIND_SERVICE"
    file_has "${d}" "CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
    file_has "${d}" "NoNewPrivileges=yes"
    file_has "${d}" "ProtectSystem=strict"
    file_has "${d}" "ReadWritePaths=/var/lib/kura/desktop"
    file_has "$(units)/kura-helper.service" "BusName=io.kura.Helper"
}

@test "install: missing programs stop the build with the reason" {
    rm "${DIST}/kura-helper"
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -ne 0 ]
    output_has "kura-helper"
}

@test "install: OS_DESKTOP=false leaves the desktop out" {
    OS_DESKTOP=false run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ ! -e "${ROOTFS}/usr/lib/kura/kura-desktopd" ]
    [ "$(jq -r '.network_security.desktop // false' "${ROOTFS}/etc/kura/security/hardening.json")" = "false" ]
}

# ---- os-desktop-cert: the device's own certificate ----

@test "cert: makes a key and a certificate for the host, and records the fingerprint" {
    local state="${BATS_TEST_TMPDIR}/state"
    DESKTOP_HOSTNAME=kura-nuc run "${CERT}" "${state}"
    [ "$status" -eq 0 ]
    [ "$(file_mode "${state}/tls.key")" = "600" ]
    run openssl x509 -in "${state}/tls.crt" -noout -ext subjectAltName
    output_has "DNS:kura-nuc.local"
    output_has "DNS:kura-nuc"
    output_has "DNS:localhost"
    local want
    want=$(openssl x509 -in "${state}/tls.crt" -noout -fingerprint -sha256 | cut -d= -f2)
    [ "$(cat "${state}/fingerprint")" = "${want}" ]
}

@test "cert: the state folder is the server's too (0750: root's would shut it out of its certificate)" {
    local state="${BATS_TEST_TMPDIR}/state" bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin}"
    printf '#!/bin/sh\necho "$@" >> "%s/chown-calls"\n' "${BATS_TEST_TMPDIR}" > "${bin}/chown"
    chmod +x "${bin}/chown"
    PATH="${bin}:${PATH}" DESKTOP_HOSTNAME=kura-nuc run "${CERT}" "${state}" kura-desktop
    [ "$status" -eq 0 ]
    grep -qx "kura-desktop:kura-desktop ${state}" "${BATS_TEST_TMPDIR}/chown-calls"
    [ "$(file_mode "${state}")" = "750" ]
}

@test "cert: an existing certificate is kept" {
    local state="${BATS_TEST_TMPDIR}/state"
    DESKTOP_HOSTNAME=kura-nuc run "${CERT}" "${state}"
    local before; before=$(cat "${state}/fingerprint")
    DESKTOP_HOSTNAME=other run "${CERT}" "${state}"
    [ "$status" -eq 0 ]
    [ "$(cat "${state}/fingerprint")" = "${before}" ]
}

@test "cert: a hostname that is not a plain name is refused" {
    DESKTOP_HOSTNAME='bad;name' run "${CERT}" "${BATS_TEST_TMPDIR}/state"
    [ "$status" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/state/tls.key" ]
}
