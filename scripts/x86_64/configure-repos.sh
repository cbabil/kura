#!/bin/bash
# scripts/x86_64/configure-repos.sh
# Configure APT repositories for the x86 PC target (firmware for real
# hardware such as the Intel NUC's Wi-Fi and GPU).
#
# Usage: configure-repos.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

# shellcheck disable=SC1091
source "$(dirname "$0")/../common/apt-components.sh"

echo "Configuring x86 APT repositories..."
add_non_free_firmware "${ROOTFS}"
echo "x86 APT repositories configured."
