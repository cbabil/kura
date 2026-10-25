#!/bin/bash
# scripts/rpi5/configure-repos.sh
# Configure APT repositories for RPi5 target.
# Runs before package installation so RPi-specific packages can be found.
#
# Usage: configure-repos.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

# shellcheck disable=SC1091
source "$(dirname "$0")/../common/apt-components.sh"

echo "Configuring RPi5 APT repositories..."

# ---- Add non-free-firmware component (for firmware-brcm80211 etc.) ----
add_non_free_firmware "${ROOTFS}"

# ---- Add Raspberry Pi APT repository ----
# [trusted=yes] required: RPi archive keyring uses SHA1 binding signatures,
# rejected by sqv since 2026-02-01. Remove trusted=yes once RPi updates their key.
install -d "${ROOTFS}/etc/apt/sources.list.d"
cat > "${ROOTFS}/etc/apt/sources.list.d/raspi.list" <<'EOF'
deb [trusted=yes] http://archive.raspberrypi.com/debian/ trixie main
EOF

echo "RPi5 APT repositories configured."
