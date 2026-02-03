#!/bin/bash
# StraturaOS Cloud Image post-image script

set -e

BOARD_DIR="$(dirname $0)"
GENIMAGE_CFG="${BOARD_DIR}/genimage-cloud.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

echo "StraturaOS Cloud: Running post-image processing..."

# Run genimage to create disk image
if [ -x "${HOST_DIR}/bin/genimage" ]; then
    rm -rf "${GENIMAGE_TMP}"
    genimage \
        --rootpath "${TARGET_DIR}" \
        --tmppath "${GENIMAGE_TMP}" \
        --inputpath "${BINARIES_DIR}" \
        --outputpath "${BINARIES_DIR}" \
        --config "${GENIMAGE_CFG}"
    echo "StraturaOS Cloud: Generated disk.img"
else
    echo "WARNING: genimage not found, skipping disk image creation"
fi

# Convert to qcow2 for Proxmox/cloud use
if [ -x "${HOST_DIR}/bin/qemu-img" ]; then
    if [ -f "${BINARIES_DIR}/disk.img" ]; then
        ${HOST_DIR}/bin/qemu-img convert -f raw -O qcow2 \
            "${BINARIES_DIR}/disk.img" \
            "${BINARIES_DIR}/straturaos-cloud.qcow2"
        echo "StraturaOS Cloud: Generated straturaos-cloud.qcow2"

        # Compress qcow2
        ${HOST_DIR}/bin/qemu-img convert -f qcow2 -O qcow2 -c \
            "${BINARIES_DIR}/straturaos-cloud.qcow2" \
            "${BINARIES_DIR}/straturaos-cloud-compressed.qcow2"
        mv "${BINARIES_DIR}/straturaos-cloud-compressed.qcow2" \
           "${BINARIES_DIR}/straturaos-cloud.qcow2"
        echo "StraturaOS Cloud: Compressed qcow2 image"
    fi
else
    echo "WARNING: qemu-img not found, skipping qcow2 conversion"
fi

# Generate checksums
cd ${BINARIES_DIR}
if [ -f straturaos-cloud.qcow2 ]; then
    sha256sum straturaos-cloud.qcow2 > straturaos-cloud.qcow2.sha256
    echo "StraturaOS Cloud: Generated SHA256 checksum"
fi

# Create version file
cat > ${BINARIES_DIR}/version.txt << EOF
StraturaOS Cloud Build Information
===================================
Version: 1.0.0
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Host: $(hostname)
Target: x86_64 Cloud/VM (Proxmox/KVM)
EOF

echo "StraturaOS Cloud: Post-image processing complete"
