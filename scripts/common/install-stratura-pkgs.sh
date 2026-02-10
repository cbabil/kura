#!/bin/bash
# scripts/common/install-stratura-pkgs.sh
# Install all Stratura packages into the rootfs.
# Replaces Buildroot .mk install targets.
#
# Usage: install-stratura-pkgs.sh <rootfs-dir> <packages-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <packages-dir>}"
PKG_DIR="${2:?Usage: $0 <rootfs-dir> <packages-dir>}"

# Resolve project root (two levels up from this script)
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Installing Stratura packages into ${ROOTFS}..."

# ---- Shared directory setup ----
install -d "${ROOTFS}/usr/lib/stratura"
touch "${ROOTFS}/usr/lib/stratura/__init__.py"
install -d "${ROOTFS}/etc/stratura"

# ---- stratura-config ----
echo "  Installing stratura-config..."
install -D -m 0755 "${PKG_DIR}/stratura-config/src/stratura-config" \
    "${ROOTFS}/usr/bin/stratura-config"
install -m 0644 "${PKG_DIR}/stratura-config/src/network_manager.py" \
    "${ROOTFS}/usr/lib/stratura/"
install -m 0644 "${PKG_DIR}/stratura-config/src/config.json" \
    "${ROOTFS}/etc/stratura/"
install -d "${ROOTFS}/etc/NetworkManager/conf.d"
install -m 0644 "${PKG_DIR}/stratura-config/src/00-stratura-network.conf" \
    "${ROOTFS}/etc/NetworkManager/conf.d/"
install -D -m 0644 "${PKG_DIR}/stratura-config/src/stratura-config.service" \
    "${ROOTFS}/usr/lib/systemd/system/stratura-config.service"

# ---- stratura-security ----
echo "  Installing stratura-security..."
install -m 0644 "${PKG_DIR}/stratura-security/src/security_hardening.py" \
    "${ROOTFS}/usr/lib/stratura/"
install -D -m 0755 "${PKG_DIR}/stratura-security/src/stratura-security" \
    "${ROOTFS}/usr/bin/stratura-security"
install -D -m 0644 "${PKG_DIR}/stratura-security/src/stratura-security.service" \
    "${ROOTFS}/usr/lib/systemd/system/stratura-security.service"

# ---- Security hardening config ----
install -d "${ROOTFS}/etc/stratura/security"
if [ -f "${PKG_DIR}/stratura-security/src/hardening.json" ]; then
    install -m 0644 "${PKG_DIR}/stratura-security/src/hardening.json" \
        "${ROOTFS}/etc/stratura/security/hardening.json"
fi

# ---- stratura-supervisor (Docker-based service) ----
echo "  Installing stratura-supervisor systemd service..."
install -D -m 0644 "${PROJECT_DIR}/supervisor/stratura-supervisor.service" \
    "${ROOTFS}/usr/lib/systemd/system/stratura-supervisor.service"

echo "Stratura packages installed."
