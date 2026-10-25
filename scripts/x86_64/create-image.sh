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

check_rootfs_fits "$(du -s -B1 "${ROOTFS}" | cut -f1)" "${ROOTFS_BYTES}"

# newest_in_boot <pattern>: the highest version of /boot/<pattern>
newest_in_boot() { find "${ROOTFS}/boot" -maxdepth 1 -name "$1" -printf '%f\n' | sort -V | tail -1; }
KERNEL=$(newest_in_boot 'vmlinuz-*')
INITRD=$(newest_in_boot 'initrd.img-*')
[ -n "${KERNEL}" ] && [ -n "${INITRD}" ] || { echo "ERROR: no kernel or initrd in ${ROOTFS}/boot" >&2; exit 1; }
while read -r src _; do
    [ -f "${ROOTFS}/${src}" ] || { echo "ERROR: missing ${src} (shim-signed, grub-efi-amd64-signed)" >&2; exit 1; }
done < <(pc_efi_files)

modprobe loop 2>/dev/null || true
echo "Creating PC disk image (${IMG_NAME})..."
mkdir -p "${OUTPUT_DIR}"
IMG="${OUTPUT_DIR}/${IMG_NAME}"

LOOP="" MNT=""
cleanup() {
    [ -n "${MNT}" ] && mountpoint -q "${MNT}" && umount "${MNT}" 2>/dev/null || true
    [ -n "${MNT}" ] && rmdir "${MNT}" 2>/dev/null || true
    [ -n "${LOOP}" ] && losetup -d "${LOOP}" 2>/dev/null || true
}
trap cleanup EXIT

truncate -s "${TOTAL_BYTES}" "${IMG}"
pc_partition_table "${EFI_MIB}" | sfdisk --quiet "${IMG}"
LOOP=$(losetup --show --partscan -f "${IMG}")

echo "  Formatting the EFI partition (FAT32) and the root (ext4)..."
mkfs.vfat -F 32 -n EFI "${LOOP}p1" >/dev/null
mkfs.ext4 -q -F -L root "${LOOP}p2"
ROOT_UUID=$(blkid -s UUID -o value "${LOOP}p2")
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${LOOP}p2")

MNT=$(mktemp -d)
mount "${LOOP}p2" "${MNT}"
echo "  Copying rootfs..."
tar -C "${ROOTFS}" -cf - . | tar -C "${MNT}" -xf -
umount "${MNT}"

mount "${LOOP}p1" "${MNT}"
echo "  Installing the signed shim + GRUB..."
while read -r src dest; do
    install -D -m 0644 "${ROOTFS}/${src}" "${MNT}/${dest}"
done < <(pc_efi_files)
pc_grub_cfg "${ROOT_UUID}" "${ROOT_PARTUUID}" "${KERNEL}" "${INITRD}" "${OS_NAME}" \
    > "${MNT}/grub.cfg.tmp"
install -D -m 0644 "${MNT}/grub.cfg.tmp" "${MNT}/$(pc_grub_cfg_path)"
mv "${MNT}/grub.cfg.tmp" "${MNT}/EFI/BOOT/grub.cfg"   # where an unsigned GRUB would look
umount "${MNT}"
rmdir "${MNT}"
MNT=""

losetup -d "${LOOP}"
LOOP=""

(cd "${OUTPUT_DIR}" && sha512sum "${IMG_NAME}" > SHA512SUMS)
echo "Created PC disk image: ${OUTPUT_DIR}/${IMG_NAME}"
