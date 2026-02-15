#!/bin/bash
# RPi5 post-image script
# Runs after the image is generated

set -e

BOARD_DIR="$(dirname $0)"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# Single source of truth for default brand values
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/common/brand-defaults.sh"

OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"

echo "${OS_NAME}: Running post-image processing..."

# Copy config.txt to images directory
if [ -f "${BOARD_DIR}/config.txt" ]; then
    cp "${BOARD_DIR}/config.txt" "${BINARIES_DIR}/config.txt"
fi

# Run genimage to create sdcard.img
if [ -x "${HOST_DIR}/bin/genimage" ]; then
    rm -rf "${GENIMAGE_TMP}"
    genimage \
        --rootpath "${TARGET_DIR}" \
        --tmppath "${GENIMAGE_TMP}" \
        --inputpath "${BINARIES_DIR}" \
        --outputpath "${BINARIES_DIR}" \
        --config "${GENIMAGE_CFG}"
    echo "${OS_NAME}: Generated sdcard.img"
else
    echo "WARNING: genimage not found, skipping SD card image creation"
fi

# Generate checksums
cd ${BINARIES_DIR}
if [ -f sdcard.img ]; then
    sha256sum sdcard.img > sdcard.img.sha256
    echo "${OS_NAME}: Generated SHA256 checksum"
fi

# Create version file
cat > ${BINARIES_DIR}/version.txt << EOF
${OS_NAME} Build Information
============================
Version: ${OS_VERSION:-1.0}
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Host: $(hostname)
Target: Raspberry Pi 5
EOF

echo "${OS_NAME}: Post-image processing complete"
