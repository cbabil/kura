#!/bin/bash
# scripts/common/install-os-pkgs.sh
# Install all OS packages into the rootfs.
#
# Usage: install-os-pkgs.sh <rootfs-dir> <packages-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <packages-dir>}"
PKG_DIR="${2:?Usage: $0 <rootfs-dir> <packages-dir>}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
# Validate BRAND (must be lowercase alphanumeric with hyphens, no shell metacharacters)
if ! [[ "${BRAND}" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: Invalid OS_BRAND '${BRAND}' (must be lowercase alphanumeric with hyphens)" >&2
    exit 1
fi
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"

echo "Installing ${OS_NAME} packages into ${ROOTFS}..."

# ---- Shared directory setup ----
install -d "${ROOTFS}/usr/lib/${BRAND}"
install -d "${ROOTFS}/etc/${BRAND}"

# ---- ${BRAND}-config ----
echo "  Installing ${BRAND}-config..."
install -D -m 0755 "${PKG_DIR}/os-config/src/os-config" \
    "${ROOTFS}/usr/bin/${BRAND}-config"
install -d "${ROOTFS}/etc/NetworkManager/conf.d"
install -m 0644 "${PKG_DIR}/os-config/src/00-os-network.conf" \
    "${ROOTFS}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf"
install -D -m 0644 "${PKG_DIR}/os-config/src/os-config.service" \
    "${ROOTFS}/usr/lib/systemd/system/${BRAND}-config.service"

# ---- ${BRAND}-security ----
echo "  Installing ${BRAND}-security..."
install -D -m 0755 "${PKG_DIR}/os-security/src/os-security" \
    "${ROOTFS}/usr/bin/${BRAND}-security"
install -D -m 0644 "${PKG_DIR}/os-security/src/os-security.service" \
    "${ROOTFS}/usr/lib/systemd/system/${BRAND}-security.service"

# Install security shell libraries
install -d "${ROOTFS}/usr/lib/${BRAND}/security"
for lib_file in "${PKG_DIR}"/os-security/src/lib/*.sh; do
    install -m 0644 "${lib_file}" "${ROOTFS}/usr/lib/${BRAND}/security/"
done

# ---- Security hardening config ----
install -d "${ROOTFS}/etc/${BRAND}/security"
if [ -f "${PKG_DIR}/os-security/src/hardening.json" ]; then
    install -m 0600 "${PKG_DIR}/os-security/src/hardening.json" \
        "${ROOTFS}/etc/${BRAND}/security/hardening.json"
fi

# Replace brand placeholders in all service files
for svc_file in "${BRAND}-config" "${BRAND}-security"; do
    sed -i "s|__BRAND__|${BRAND}|g; s|__BRAND_NAME__|${OS_NAME}|g" \
        "${ROOTFS}/usr/lib/systemd/system/${svc_file}.service"
done

# Patch shell scripts: replace __BRAND__ placeholder with actual brand
for script in "${ROOTFS}/usr/bin/${BRAND}-config" \
              "${ROOTFS}/usr/bin/${BRAND}-security"; do
    if [ -f "${script}" ]; then
        sed -i "s|__BRAND__|${BRAND}|g" "${script}"
    fi
done

# Patch security library files: replace __BRAND__ placeholder
for lib_file in "${ROOTFS}/usr/lib/${BRAND}/security"/*.sh; do
    if [ -f "${lib_file}" ]; then
        sed -i "s|__BRAND__|${BRAND}|g" "${lib_file}"
    fi
done

echo "${OS_NAME} packages installed."
