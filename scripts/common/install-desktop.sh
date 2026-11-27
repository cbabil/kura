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

for program in kura-desktopd kura-helper kura-agent; do
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
# The file agent, which the helper has systemd run as the signed-in user (ADR-031)
put "${DIST}/kura-agent" "${lib}/${BRAND}-agent" 0755
brand "${SRC}/os-desktop-cert" "${lib}/${BRAND}-desktop-cert" 0755
brand "${SRC}/os-settings" "${lib}/${BRAND}-settings" 0755
brand "${SRC}/os-settings-screens" "${lib}/${BRAND}-settings-screens" 0644
# The App Catalog (ADR-032): the root command and the templates it installs
brand "${SRC}/os-apps" "${lib}/${BRAND}-apps" 0755
for template in "${SRC}"/../catalog/*/; do
    put "${template}app.json" "${lib}/catalog/$(basename "${template}")/app.json" 0644
    put "${template}compose.yaml" "${lib}/catalog/$(basename "${template}")/compose.yaml" 0644
done
brand "${SRC}/avahi-desktop.service" "${ROOTFS}/etc/avahi/services/${BRAND}-desktop.service" 0644
brand "${SRC}/os-desktop.service" "${units}/${BRAND}-desktopd.service" 0644
brand "${SRC}/os-helper.service" "${units}/${BRAND}-helper.service" 0644
brand "${SRC}/os-desktop-cert.service" "${units}/${BRAND}-desktop-cert.service" 0644
brand "${SRC}/os-network-pending.service" "${units}/${BRAND}-network-pending.service" 0644
brand "${SRC}/io.kura.Helper.conf" "${ROOTFS}/usr/share/dbus-1/system.d/io.kura.Helper.conf" 0644
brand "${SRC}/sysusers.conf" "${ROOTFS}/usr/lib/sysusers.d/${BRAND}-desktop.conf" 0644
brand "${SRC}/tmpfiles.conf" "${ROOTFS}/usr/lib/tmpfiles.d/${BRAND}-desktop.conf" 0644

for unit in desktopd helper desktop-cert network-pending; do
    enable_unit "${ROOTFS}" multi-user.target "/usr/lib/systemd/system/${BRAND}-${unit}.service"
done

# The local screen (ADR-033), and the same way Remote Desktop (ADR-035) and
# the Browser (ADR-036). Its unit, user and command are in every PC
# image (OS_KIOSK_FILES, set by build.sh), so the kura package is the same
# for all PCs and an upgrade takes nothing away; they do nothing without
# the browser, which only an image built with OS_KIOSK has and turns on.
if [ "${OS_KIOSK_FILES:-false}" = "true" ]; then
    brand "${SRC}/os-kiosk" "${lib}/${BRAND}-kiosk" 0755
    brand "${SRC}/os-kiosk.service" "${units}/${BRAND}-kiosk.service" 0644
    brand "${SRC}/sysusers-kiosk.conf" "${ROOTFS}/usr/lib/sysusers.d/${BRAND}-kiosk.conf" 0644
    # Remote Desktop (ADR-035): Debian's xrdp, where the image has it
    # (OS_KIOSK). Kura's part is what a session shows and who may connect.
    # apt turned xrdp on when it installed it; it opens a port, so it is
    # off here and Settings turns it on.
    brand "${SRC}/os-rdp-session" "${lib}/${BRAND}-rdp-session" 0755
    brand "${SRC}/xrdp-dropin.conf" "${units}/xrdp.service.d/10-${BRAND}.conf" 0644
    disable_unit "${ROOTFS}" multi-user.target xrdp.service
    disable_unit "${ROOTFS}" multi-user.target xrdp-sesman.service
    # The Browser (ADR-036): the command each person's browser runs, as
    # them, when the helper starts it; its programs come with OS_BROWSER.
    brand "${SRC}/os-browser" "${lib}/${BRAND}-browser" 0755
    if [ "${OS_KIOSK:-false}" = "true" ]; then
        enable_unit "${ROOTFS}" multi-user.target "/usr/lib/systemd/system/${BRAND}-kiosk.service"
    fi
fi

# The firewall opens 443 to local networks when this is set (lib/firewall.sh)
hardening="${ROOTFS}/etc/${BRAND}/security/hardening.json"
if [ -f "${hardening}" ]; then
    jq '.network_security.desktop = true' "${hardening}" > "${hardening}.tmp"
    cat "${hardening}.tmp" > "${hardening}" && rm -f "${hardening}.tmp"
fi

echo "  ${NAME} Desktop installed."
