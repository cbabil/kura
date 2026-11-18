#!/bin/bash
# scripts/common/install-desktop.sh
# Installs Kura Desktop (ADR-023, ADR-024) into the rootfs: the server and
# the helper built under desktop/dist/<arch>/, their units, D-Bus policy,
# user and state folder, and the firewall switch for port 443.
# OS_DESKTOP=false leaves it out.
#
# Usage: install-desktop.sh <rootfs-dir> <packages-dir> <dist-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <packages-dir> <dist-dir>}"
PKG_DIR="${2:?Usage: $0 <rootfs-dir> <packages-dir> <dist-dir>}"
DIST="${3:?Usage: $0 <rootfs-dir> <packages-dir> <dist-dir>}"

# shellcheck disable=SC1091
source "$(dirname "$0")/brand-defaults.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/systemd-units.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
NAME="${OS_NAME:-${DEFAULT_NAME}}"
SRC="${PKG_DIR}/os-desktop/src"

if [ "${OS_DESKTOP:-true}" = "false" ]; then
    echo "  Kura Desktop left out (OS_DESKTOP=false)."
    exit 0
fi

for program in kura-desktopd kura-helper; do
    if [ ! -f "${DIST}/${program}" ]; then
        echo "ERROR: ${DIST}/${program} is missing; build it first (make -C desktop dist)" >&2
        exit 1
    fi
done

echo "  Installing ${NAME} Desktop..."

# put <src> <dest> <mode>: copy, making the folder (portable: no install -D)
put() {
    install -d "$(dirname "$2")"
    install -m "$3" "$1" "$2"
}

# brand <src> <dest> <mode>: put, with the brand placeholders filled in
brand() {
    put "$1" "$2" "$3"
    sed -i.bak "s|__BRAND_NAME__|${NAME}|g; s|__BRAND__|${BRAND}|g" "$2" && rm -f "$2.bak"
}

lib="${ROOTFS}/usr/lib/${BRAND}"
units="${ROOTFS}/usr/lib/systemd/system"
put "${DIST}/kura-desktopd" "${lib}/${BRAND}-desktopd" 0755
put "${DIST}/kura-helper" "${lib}/${BRAND}-helper" 0755
brand "${SRC}/os-desktop-cert" "${lib}/${BRAND}-desktop-cert" 0755
brand "${SRC}/os-desktop.service" "${units}/${BRAND}-desktopd.service" 0644
brand "${SRC}/os-helper.service" "${units}/${BRAND}-helper.service" 0644
brand "${SRC}/os-desktop-cert.service" "${units}/${BRAND}-desktop-cert.service" 0644
brand "${SRC}/io.kura.Helper.conf" "${ROOTFS}/usr/share/dbus-1/system.d/io.kura.Helper.conf" 0644
brand "${SRC}/sysusers.conf" "${ROOTFS}/usr/lib/sysusers.d/${BRAND}-desktop.conf" 0644
brand "${SRC}/tmpfiles.conf" "${ROOTFS}/usr/lib/tmpfiles.d/${BRAND}-desktop.conf" 0644

for unit in desktopd helper desktop-cert; do
    enable_unit "${ROOTFS}" multi-user.target "/usr/lib/systemd/system/${BRAND}-${unit}.service"
done

# The firewall opens 443 to local networks when this is set (lib/firewall.sh)
hardening="${ROOTFS}/etc/${BRAND}/security/hardening.json"
if [ -f "${hardening}" ]; then
    jq '.network_security.desktop = true' "${hardening}" > "${hardening}.tmp"
    cat "${hardening}.tmp" > "${hardening}" && rm -f "${hardening}.tmp"
fi

echo "  ${NAME} Desktop installed."
