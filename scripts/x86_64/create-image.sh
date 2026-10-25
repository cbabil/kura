#!/bin/bash
# scripts/x86_64/create-image.sh
# Create the x86 PC disk image (UEFI, GPT) from a prepared rootfs. Written
# with an imager to a USB drive or SSD that the PC (e.g. an Intel NUC) boots
# from and keeps running from. Layout in pc-image.sh.
#
# Usage: create-image.sh <rootfs-dir> <output-dir>
# Requires: sfdisk, losetup, mkfs.vfat, mkfs.ext4, blkid (root required)

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <output-dir>}"
OUTPUT_DIR="${2:?Usage: $0 <rootfs-dir> <output-dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/brand-defaults.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/image-size.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/disk-image.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/pc-image.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
VERSION="${OS_VERSION:-2.0}"
# Firmware and full kernel modules make the PC root larger than the Pi's
ROOTFS_SIZE="${OS_PC_ROOTFS_SIZE:-3G}"
EFI_MIB=256
BUILD_SEQ="${OS_BUILD_SEQ:-0001}"
IMG_NAME="${BRAND}-${VERSION}-x86_64-amd64-${BUILD_DATE:-$(date +%Y%m%d)}-${BUILD_SEQ}.img"

ROOTFS_BYTES=$(numfmt --from=iec "${ROOTFS_SIZE}")
# +2 MiB: the 1 MiB alignment before p1 and the backup GPT after p2
TOTAL_BYTES=$(( EFI_MIB * 1024 * 1024 + ROOTFS_BYTES + 2 * 1024 * 1024 ))

check_rootfs_fits "$(du -s -B1 "${ROOTFS}" | cut -f1)" "${ROOTFS_BYTES}" OS_PC_ROOTFS_SIZE

# GRUB boots the kernel packages' /vmlinuz and /initrd.img symlinks
for link in vmlinuz initrd.img; do
    [ -e "${ROOTFS}/${link}" ] || { echo "ERROR: no /${link} in ${ROOTFS}" >&2; exit 1; }
done
while read -r src _; do
    [ -f "${ROOTFS}/${src}" ] || { echo "ERROR: missing ${src} (shim-signed, grub-efi-amd64-signed)" >&2; exit 1; }
done < <(pc_efi_files)

echo "Creating PC disk image (${IMG_NAME})..."
mkdir -p "${OUTPUT_DIR}"
IMG="${OUTPUT_DIR}/${IMG_NAME}"

truncate -s "${TOTAL_BYTES}" "${IMG}"
pc_partition_table "${EFI_MIB}" | sfdisk --quiet "${IMG}"
disk_image_attach "${IMG}"
EFI_PART="${DISK_IMAGE_LOOP}p1"
ROOT_PART="${DISK_IMAGE_LOOP}p2"

echo "  Formatting the EFI partition (FAT32) and the root (ext4)..."
mkfs.vfat -F 32 -n EFI "${EFI_PART}" >/dev/null
mkfs.ext4 -q -F -L root "${ROOT_PART}"
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PART}")
EFI_PARTUUID=$(blkid -s PARTUUID -o value "${EFI_PART}")

disk_image_copy_rootfs "${ROOTFS}" "${ROOT_PART}"
disk_image_mount "${ROOT_PART}"
pc_fstab "${ROOT_PARTUUID}" "${EFI_PARTUUID}" > "${DISK_IMAGE_MNT}/etc/fstab"
disk_image_unmount

disk_image_mount "${EFI_PART}"
echo "  Installing the signed shim + GRUB..."
while read -r src dest; do
    mkdir -p "$(dirname "${DISK_IMAGE_MNT}/${dest}")"
    cp "${ROOTFS}/${src}" "${DISK_IMAGE_MNT}/${dest}"
done < <(pc_efi_files)
mkdir -p "$(dirname "${DISK_IMAGE_MNT}/${PC_GRUB_CFG}")"
pc_grub_cfg "${ROOT_UUID}" "${ROOT_PARTUUID}" "${OS_NAME}" > "${DISK_IMAGE_MNT}/${PC_GRUB_CFG}"
disk_image_unmount

disk_image_finish "${IMG}"
echo "Created PC disk image: ${IMG}"
