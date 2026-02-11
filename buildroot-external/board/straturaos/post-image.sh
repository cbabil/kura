#!/bin/bash
# StraturaOS post-image script
# Runs after the image is generated

set -e

BOARD_DIR="$(dirname $0)"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

echo "StraturaOS: Running post-image processing..."

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
    echo "StraturaOS: Generated sdcard.img"
else
    echo "WARNING: genimage not found, skipping SD card image creation"
fi

# Generate checksums
cd ${BINARIES_DIR}
if [ -f sdcard.img ]; then
    sha256sum sdcard.img > sdcard.img.sha256
    echo "StraturaOS: Generated SHA256 checksum"
fi

# Create version file
cat > ${BINARIES_DIR}/version.txt << EOF
StraturaOS Build Information
============================
Version: ${STRATURAOS_VERSION:-1.0}
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Host: $(hostname)
Target: Raspberry Pi 5
EOF

echo "StraturaOS: Post-image processing complete"
