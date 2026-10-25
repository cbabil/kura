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

# Ensure loop device kernel module is loaded
modprobe loop 2>/dev/null || true

echo "Creating RPi5 SD card image (${IMG_NAME})..."

mkdir -p "${OUTPUT_DIR}"
IMG="${OUTPUT_DIR}/${IMG_NAME}"

# Track resources for cleanup
LOOP=""
BOOT_MNT=""
ROOT_MNT=""

cleanup() {
    echo "Cleaning up..."
    [ -n "${ROOT_MNT}" ] && mountpoint -q "${ROOT_MNT}" && umount "${ROOT_MNT}" 2>/dev/null || true
    [ -n "${ROOT_MNT}" ] && [ -d "${ROOT_MNT}" ] && rmdir "${ROOT_MNT}" 2>/dev/null || true
    [ -n "${BOOT_MNT}" ] && mountpoint -q "${BOOT_MNT}" && umount "${BOOT_MNT}" 2>/dev/null || true
    [ -n "${BOOT_MNT}" ] && [ -d "${BOOT_MNT}" ] && rmdir "${BOOT_MNT}" 2>/dev/null || true
    [ -n "${LOOP}" ] && losetup -d "${LOOP}" 2>/dev/null || true
}
trap cleanup EXIT

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
LOOP=$(losetup --show --partscan -f "${IMG}")

# ---- Format partitions ----
echo "  Formatting boot partition (FAT32)..."
mkfs.vfat -F 32 "${LOOP}p1"
echo "  Formatting rootfs partition (ext4)..."
mkfs.ext4 -F "${LOOP}p2"

# ---- Mount and populate boot partition ----
BOOT_MNT=$(mktemp -d)
mount "${LOOP}p1" "${BOOT_MNT}"

# Copy kernel (try vmlinuz first, then Image)
if ls "${ROOTFS}"/boot/vmlinuz-* 1>/dev/null 2>&1; then
    cp "${ROOTFS}"/boot/vmlinuz-* "${BOOT_MNT}/vmlinuz"
    echo "  Copied kernel: vmlinuz"
elif [ -f "${ROOTFS}/boot/Image" ]; then
    cp "${ROOTFS}/boot/Image" "${BOOT_MNT}/"
    echo "  Copied kernel: Image"
else
    echo "ERROR: No kernel found in ${ROOTFS}/boot/"
    exit 1
fi

# Copy device tree (try multiple paths)
DTB_COPIED=false
for dtb_path in \
    "${ROOTFS}"/boot/dtbs/*/broadcom/bcm2712-rpi-5-b.dtb \
    "${ROOTFS}/boot/broadcom/bcm2712-rpi-5-b.dtb" \
    "${ROOTFS}/boot/bcm2712-rpi-5-b.dtb" \
    "${ROOTFS}/usr/lib/linux-image-"*/broadcom/bcm2712-rpi-5-b.dtb; do
    # shellcheck disable=SC2086
    if ls ${dtb_path} 1>/dev/null 2>&1; then
        # shellcheck disable=SC2086
        cp ${dtb_path} "${BOOT_MNT}/bcm2712-rpi-5-b.dtb"
        DTB_COPIED=true
        echo "  Copied DTB: bcm2712-rpi-5-b.dtb"
        break
    fi
done
if [ "${DTB_COPIED}" = "false" ]; then
    echo "WARNING: DTB bcm2712-rpi-5-b.dtb not found -- boot may fail"
fi

# Copy DTB overlays (try multiple paths)
for overlay_path in \
    "${ROOTFS}"/boot/dtbs/*/overlays \
    "${ROOTFS}/boot/overlays" \
    "${ROOTFS}/usr/lib/linux-image-"*/overlays; do
    # shellcheck disable=SC2086
    if ls -d ${overlay_path} 1>/dev/null 2>&1; then
        # shellcheck disable=SC2086
        cp -r ${overlay_path} "${BOOT_MNT}/"
        echo "  Copied DTB overlays"
        break
    fi
done

# Copy RPi firmware files (try multiple paths)
for fw_file in start4.elf fixup4.dat bootcode.bin; do
    FW_COPIED=false
    for fw_path in \
        "${ROOTFS}/boot/firmware/${fw_file}" \
        "${ROOTFS}/usr/lib/raspi-firmware/${fw_file}" \
        "${ROOTFS}/boot/${fw_file}"; do
        if [ -f "${fw_path}" ]; then
            cp "${fw_path}" "${BOOT_MNT}/"
            FW_COPIED=true
            break
        fi
    done
    if [ "${FW_COPIED}" = "false" ]; then
        echo "WARNING: Firmware file ${fw_file} not found"
    fi
done

# Copy config.txt
cp "${SCRIPT_DIR}/config.txt" "${BOOT_MNT}/"
echo "  Copied config.txt"

# Copy cmdline.txt (root mounted read-write: the image ships no /etc/fstab)
cp "${SCRIPT_DIR}/cmdline.txt" "${BOOT_MNT}/"
echo "  Copied cmdline.txt"

umount "${BOOT_MNT}"
rmdir "${BOOT_MNT}"
BOOT_MNT=""

# ---- Mount and populate rootfs partition ----
ROOT_MNT=$(mktemp -d)
mount "${LOOP}p2" "${ROOT_MNT}"

echo "  Copying rootfs via tar..."
tar -C "${ROOTFS}" -cf - . | tar -C "${ROOT_MNT}" -xf -
echo "  Rootfs copy complete."

umount "${ROOT_MNT}"
rmdir "${ROOT_MNT}"
ROOT_MNT=""

# ---- Detach loop device ----
losetup -d "${LOOP}"
LOOP=""

# ---- Checksums ----
(cd "${OUTPUT_DIR}" && sha512sum "${IMG_NAME}" > SHA512SUMS)

echo "Created RPi5 SD card image: ${OUTPUT_DIR}/${IMG_NAME}"
