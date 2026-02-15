#!/bin/bash
# scripts/common/install-os-pkgs.sh
# Install all OS packages into the rootfs.
# Replaces Buildroot .mk install targets.
#
# Usage: install-os-pkgs.sh <rootfs-dir> <packages-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <packages-dir>}"
PKG_DIR="${2:?Usage: $0 <rootfs-dir> <packages-dir>}"

# Resolve project root (two levels up from this script)
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
API_ENDPOINT="${OS_API_ENDPOINT:-${DEFAULT_API_ENDPOINT}}"
REGISTRY="${OS_REGISTRY:-${DEFAULT_REGISTRY}}"
# Extract domain from API_ENDPOINT (strip protocol prefix)
API_DOMAIN="${API_ENDPOINT#*://}"
# Derive base domain and updates domain
BASE_DOMAIN="${API_DOMAIN#*.}"
UPDATES_DOMAIN="updates.${BASE_DOMAIN}"

echo "Installing ${OS_NAME} packages into ${ROOTFS}..."

# ---- Shared directory setup ----
install -d "${ROOTFS}/usr/lib/${BRAND}"
touch "${ROOTFS}/usr/lib/${BRAND}/__init__.py"
install -d "${ROOTFS}/etc/${BRAND}"

# ---- ${BRAND}-config ----
echo "  Installing ${BRAND}-config..."
install -D -m 0755 "${PKG_DIR}/os-config/src/os-config" \
    "${ROOTFS}/usr/bin/${BRAND}-config"
install -m 0644 "${PKG_DIR}/os-config/src/network_manager.py" \
    "${ROOTFS}/usr/lib/${BRAND}/"
install -m 0644 "${PKG_DIR}/os-config/src/config.json" \
    "${ROOTFS}/etc/${BRAND}/"
install -d "${ROOTFS}/etc/NetworkManager/conf.d"
install -m 0644 "${PKG_DIR}/os-config/src/00-os-network.conf" \
    "${ROOTFS}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf"
install -D -m 0644 "${PKG_DIR}/os-config/src/os-config.service" \
    "${ROOTFS}/usr/lib/systemd/system/${BRAND}-config.service"

# ---- ${BRAND}-security ----
echo "  Installing ${BRAND}-security..."
install -m 0644 "${PKG_DIR}/os-security/src/security_hardening.py" \
    "${ROOTFS}/usr/lib/${BRAND}/"
install -D -m 0755 "${PKG_DIR}/os-security/src/os-security" \
    "${ROOTFS}/usr/bin/${BRAND}-security"
install -D -m 0644 "${PKG_DIR}/os-security/src/os-security.service" \
    "${ROOTFS}/usr/lib/systemd/system/${BRAND}-security.service"

# ---- Security hardening config ----
install -d "${ROOTFS}/etc/${BRAND}/security"
if [ -f "${PKG_DIR}/os-security/src/hardening.json" ]; then
    install -m 0644 "${PKG_DIR}/os-security/src/hardening.json" \
        "${ROOTFS}/etc/${BRAND}/security/hardening.json"
fi

# ---- ${BRAND}-supervisor (systemd service) ----
echo "  Installing ${BRAND}-supervisor systemd service..."
install -D -m 0644 "${PROJECT_DIR}/supervisor/os-supervisor.service" \
    "${ROOTFS}/usr/lib/systemd/system/${BRAND}-supervisor.service"

# Replace brand placeholders in all service files
for svc_file in "${BRAND}-supervisor" "${BRAND}-config" "${BRAND}-security"; do
    sed -i "s|__BRAND__|${BRAND}|g; s|__BRAND_NAME__|${OS_NAME}|g; s|__BRAND_API__|${API_DOMAIN}|g" \
        "${ROOTFS}/usr/lib/systemd/system/${svc_file}.service"
done

# Replace brand placeholder in NetworkManager config
sed -i "s|__BRAND_API__|${API_DOMAIN}|g" \
    "${ROOTFS}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf"

# Patch Python sources: replace __BRAND__ placeholder with actual brand
for pyfile in "${ROOTFS}/usr/lib/${BRAND}/security_hardening.py" \
              "${ROOTFS}/usr/lib/${BRAND}/network_manager.py"; do
    if [ -f "${pyfile}" ]; then
        sed -i "s|__BRAND__|${BRAND}|g" "${pyfile}"
    fi
done

# Patch hardening.json: replace domain placeholders with actual values
if [ -f "${ROOTFS}/etc/${BRAND}/security/hardening.json" ]; then
    sed -i "s|__REGISTRY__|${REGISTRY}|g; \
            s|__API_DOMAIN__|${API_DOMAIN}|g; \
            s|__UPDATES_DOMAIN__|${UPDATES_DOMAIN}|g" \
        "${ROOTFS}/etc/${BRAND}/security/hardening.json"
fi

echo "${OS_NAME} packages installed."
