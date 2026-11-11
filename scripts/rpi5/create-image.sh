#!/bin/bash
# scripts/rpi5/create-image.sh
# Create RPi5 SD card image using sfdisk + losetup.
#
# Usage: create-image.sh <rootfs-dir> <output-dir>
# Requires: sfdisk, losetup, mkfs.vfat, mkfs.ext4 (root required)

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <output-dir>}"
OUTPUT_DIR="${2:?Usage: $0 <rootfs-dir> <output-dir>}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/../common/brand-defaults.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/../common/image-size.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/../common/disk-image.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/boot-files.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
VERSION="${OS_VERSION:-2.0}"
ROOTFS_SIZE="${OS_ROOTFS_SIZE:-2G}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_SEQ="${OS_BUILD_SEQ:-0001}"
IMG_NAME="${BRAND}-${VERSION}-rpi5-arm64-${BUILD_DATE:-$(date +%Y%m%d)}-${BUILD_SEQ}.img"

# Calculate total image size
BOOT_BYTES=$((256 * 1024 * 1024))
ROOTFS_BYTES=$(numfmt --from=iec "${ROOTFS_SIZE}")
TOTAL_BYTES=$(( BOOT_BYTES + ROOTFS_BYTES + (4 * 1024 * 1024) ))  # +4M alignment

# Fail early, with the fix, if the rootfs cannot fit its partition
check_rootfs_fits "$(du -s -B1 "${ROOTFS}" | cut -f1)" "${ROOTFS_BYTES}"

echo "Creating RPi5 SD card image (${IMG_NAME})..."

mkdir -p "${OUTPUT_DIR}"
IMG="${OUTPUT_DIR}/${IMG_NAME}"

# ---- Create image file ----
truncate -s "${TOTAL_BYTES}" "${IMG}"

# ---- Partition with sfdisk (MBR) ----
BOOT_SECTORS=$((BOOT_BYTES / 512))
sfdisk "${IMG}" <<EOF
label: dos
unit: sectors

# Partition 1: FAT32 boot (256M)
start=2048, size=${BOOT_SECTORS}, type=c, bootable

# Partition 2: ext4 rootfs (rest)
start=$(( 2048 + BOOT_SECTORS )), type=83
EOF

# ---- Setup loop device ----
disk_image_attach "${IMG}"
LOOP="${DISK_IMAGE_LOOP}"

# ---- Format partitions ----
echo "  Formatting boot partition (FAT32)..."
mkfs.vfat -F 32 "${LOOP}p1"
echo "  Formatting rootfs partition (ext4)..."
mkfs.ext4 -F "${LOOP}p2"

# ---- Mount and populate boot partition ----
disk_image_mount "${LOOP}p1"
BOOT_MNT="${DISK_IMAGE_MNT}"

# Kernel (as vmlinuz, config.txt's kernel=), device tree and overlays; the
# device's kernel hook copies later kernels the same way (boot-files.sh)
copy_kernel_files "${ROOTFS}" "${BOOT_MNT}"

# RPi firmware files
for fw_file in start4.elf fixup4.dat bootcode.bin; do
    if fw_path=$(first_existing "${ROOTFS}/boot/firmware/${fw_file}" \
            "${ROOTFS}/usr/lib/raspi-firmware/${fw_file}" "${ROOTFS}/boot/${fw_file}"); then
        cp "${fw_path}" "${BOOT_MNT}/"
    else
        echo "WARNING: Firmware file ${fw_file} not found"
    fi
done

# Copy config.txt
cp "${SCRIPT_DIR}/config.txt" "${BOOT_MNT}/"
echo "  Copied config.txt"

# Copy cmdline.txt (root mounted read-write: the image ships no /etc/fstab)
cp "${SCRIPT_DIR}/cmdline.txt" "${BOOT_MNT}/"
echo "  Copied cmdline.txt"

disk_image_unmount

# ---- Populate the rootfs partition, detach, checksum ----
disk_image_copy_rootfs "${ROOTFS}" "${LOOP}p2"
disk_image_finish "${IMG}"

echo "Created RPi5 SD card image: ${OUTPUT_DIR}/${IMG_NAME}"
