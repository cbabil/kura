#!/bin/bash
# scripts/pc-installer/create-image.sh
# Build the PC installer image (target pc-installer, ADR-017): a small UEFI
# USB image that boots Debian's signed kernel with the installer initrd and
# writes the latest Kura PC image to the PC's internal drive. Layout in
# installer-image.sh. The throwaway rootfs only supplies the signed boot
# files, the kernel and the initrd's contents.
#
# Usage: create-image.sh <output-dir> <debian-suite> <debian-mirror> <tmp-dir>
# Requires: mmdebstrap, sfdisk, losetup, mkfs.vfat (root required)

set -euo pipefail

USAGE="Usage: $0 <output-dir> <debian-suite> <debian-mirror> <tmp-dir>"
OUTPUT_DIR="${1:?${USAGE}}"
SUITE="${2:?${USAGE}}"
MIRROR="${3:?${USAGE}}"
TMP_DIR="${4:?${USAGE}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/brand-defaults.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/disk-image.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/installer-image.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
VERSION="${OS_VERSION:-2.0}"
EFI_MIB=128
BUILD_SEQ="${OS_BUILD_SEQ:-0001}"
IMG_NAME="${BRAND}-${VERSION}-x86_64-installer-${BUILD_DATE:-$(date +%Y%m%d)}-${BUILD_SEQ}.img"
ROOTFS="${TMP_DIR}/${BRAND}-rootfs-pc-installer"
INITRD="${TMP_DIR}/${BRAND}-installer-initrd.img"

cleanup() {
    disk_image_cleanup
    rm -rf "${ROOTFS}" "${INITRD}"
}
trap cleanup EXIT

echo "Bootstrapping the installer's build rootfs..."
rm -rf "${ROOTFS}"
KEYRING=()
[ -f /usr/share/keyrings/debian-archive-keyring.gpg ] &&
    KEYRING=(--keyring=/usr/share/keyrings/debian-archive-keyring.gpg)
# The kernel package would build an initramfs nobody uses: skip it
mmdebstrap --variant=minbase --arch=amd64 --quiet --components=main,non-free-firmware \
    "${KEYRING[@]}" \
    --essential-hook='chroot "$1" dpkg-divert --local --rename --add /usr/sbin/update-initramfs && ln -s /bin/true "$1/usr/sbin/update-initramfs"' \
    --include="$(grep -v '^#' "${REPO_DIR}/config/packages-pc-installer.list" | grep -v '^$' | paste -sd, -)" \
    "${SUITE}" "${ROOTFS}" "${MIRROR}"

KVER=$(basename "$(readlink -f "${ROOTFS}/vmlinuz")" | sed 's/^vmlinuz-//')
echo "Building the initrd (kernel ${KVER})..."
"${SCRIPT_DIR}/build-initrd.sh" "${ROOTFS}" "${KVER}" "${INITRD}"

while read -r src _; do
    [ -f "${ROOTFS}/${src}" ] || { echo "ERROR: missing ${src}" >&2; exit 1; }
done < <(installer_files)

echo "Creating the installer image (${IMG_NAME})..."
mkdir -p "${OUTPUT_DIR}"
IMG="${OUTPUT_DIR}/${IMG_NAME}"
# +2 MiB: the 1 MiB alignment before p1 and the backup GPT after it
truncate -s $(( (EFI_MIB + 2) * 1024 * 1024 )) "${IMG}"
installer_partition_table "${EFI_MIB}" | sfdisk --quiet "${IMG}"
disk_image_attach "${IMG}"
mkfs.vfat -F 32 -n "${INSTALLER_LABEL}" "${DISK_IMAGE_LOOP}p1" >/dev/null

disk_image_mount "${DISK_IMAGE_LOOP}p1"
while read -r src dest; do
    mkdir -p "$(dirname "${DISK_IMAGE_MNT}/${dest}")"
    cp -L "${ROOTFS}/${src}" "${DISK_IMAGE_MNT}/${dest}"
done < <(installer_files)
cp "${INITRD}" "${DISK_IMAGE_MNT}/kura/initrd.img"
mkdir -p "$(dirname "${DISK_IMAGE_MNT}/${PC_GRUB_CFG}")"
installer_grub_cfg "${INSTALLER_LABEL}" "${OS_NAME}" > "${DISK_IMAGE_MNT}/${PC_GRUB_CFG}"
disk_image_unmount

disk_image_finish "${IMG}"
echo "Created PC installer image: ${IMG} ($(du -h "${IMG}" | cut -f1))"
