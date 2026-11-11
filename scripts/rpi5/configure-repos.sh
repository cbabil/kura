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
# shellcheck disable=SC1091
source "$(dirname "$0")/raspi-repo.sh"

echo "Configuring RPi5 APT repositories..."

# ---- Add non-free-firmware component (for firmware-brcm80211 etc.) ----
add_non_free_firmware "${ROOTFS}"
# ---- Debian's security and updates suites ----
add_debian_updates "${ROOTFS}"

# ---- Raspberry Pi APT repository, checked with the pinned key ----
install_raspi_repo "${ROOTFS}"

echo "RPi5 APT repositories configured."
