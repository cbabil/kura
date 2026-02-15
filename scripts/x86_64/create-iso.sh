#!/bin/bash
# scripts/x86_64/create-iso.sh
# Create hybrid BIOS+EFI ISO from a prepared rootfs.
#
# Usage: create-iso.sh <rootfs-dir> <output-dir>
# Requires: xorriso, grub-pc-bin, grub-efi-amd64-bin, mtools, squashfs-tools

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir> <output-dir>}"
OUTPUT_DIR="${2:?Usage: $0 <rootfs-dir> <output-dir>}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/../common/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
VERSION="${OS_VERSION:-2.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_DIR="${OS_TMP:-/tmp}/${BRAND}os-iso-$$"
BUILD_SEQ="${OS_BUILD_SEQ:-0001}"
ISO_NAME="${BRAND}os-${VERSION}-x86_64-amd64-${BUILD_DATE:-$(date +%Y%m%d)}-${BUILD_SEQ}.iso"
VOLID=$(echo "${BRAND}OS" | tr '[:lower:]' '[:upper:]')

# GRUB module paths (system packages at known locations)
GRUB_I386_DIR="/usr/lib/grub/i386-pc"
GRUB_X64_EFI_DIR="/usr/lib/grub/x86_64-efi"

trap 'rm -rf "${ISO_DIR}"' EXIT

echo "Creating hybrid BIOS+EFI ISO..."

# ---- Validate prerequisites ----
for f in "${GRUB_I386_DIR}/cdboot.img" "${GRUB_I386_DIR}/boot_hybrid.img"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing $f -- install grub-pc-bin"
        exit 1
    fi
done

# ---- Stage ISO directory ----
mkdir -p "${ISO_DIR}/boot/grub"
mkdir -p "${ISO_DIR}/EFI"
mkdir -p "${ISO_DIR}/live"

# ---- Create squashfs from rootfs ----
echo "  Creating squashfs (xz compression)..."
mksquashfs "${ROOTFS}" "${ISO_DIR}/live/filesystem.squashfs" \
    -comp xz -no-exports -noappend -quiet

# ---- Copy kernel + initrd ----
cp "${ROOTFS}"/boot/vmlinuz-* "${ISO_DIR}/boot/vmlinuz"
cp "${ROOTFS}"/boot/initrd.img-* "${ISO_DIR}/boot/initrd.img"

# ---- Copy GRUB config and patch OS name ----
cp "${SCRIPT_DIR}/grub.cfg" "${ISO_DIR}/boot/grub/grub.cfg"
sed -i "s/${DEFAULT_NAME}/${OS_NAME}/g" "${ISO_DIR}/boot/grub/grub.cfg"

# ---- Create GRUB BIOS boot image ----
echo "  Creating GRUB BIOS image..."
grub-mkimage \
    -O i386-pc \
    -d "${GRUB_I386_DIR}" \
    -o "${ISO_DIR}/boot/grub/core.img" \
    -p /boot/grub \
    biosdisk iso9660 linux normal search configfile part_msdos part_gpt ext2 fat

cat "${GRUB_I386_DIR}/cdboot.img" "${ISO_DIR}/boot/grub/core.img" \
    > "${ISO_DIR}/boot/grub/bios.img"

# ---- Create EFI boot image ----
echo "  Creating EFI boot image..."
truncate -s 4M "${ISO_DIR}/EFI/efiboot.img"
mkfs.vfat "${ISO_DIR}/EFI/efiboot.img"
mmd -i "${ISO_DIR}/EFI/efiboot.img" ::/EFI ::/EFI/BOOT

# Find EFI binary: try system grubx64.efi first, fallback to building one
EFI_BINARY="${GRUB_X64_EFI_DIR}/../grubx64.efi"
if [ ! -f "${EFI_BINARY}" ]; then
    # Build one from modules
    grub-mkimage \
        -O x86_64-efi \
        -d "${GRUB_X64_EFI_DIR}" \
        -o "${ISO_DIR}/boot/grub/bootx64.efi" \
        -p /boot/grub \
        boot linux ext2 fat iso9660 part_msdos part_gpt normal efi_gop
    EFI_BINARY="${ISO_DIR}/boot/grub/bootx64.efi"
fi

mcopy -i "${ISO_DIR}/EFI/efiboot.img" "${EFI_BINARY}" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "${ISO_DIR}/EFI/efiboot.img" "${ISO_DIR}/boot/grub/grub.cfg" ::/EFI/BOOT/grub.cfg

# ---- Assemble hybrid ISO ----
echo "  Assembling hybrid ISO with xorriso..."
mkdir -p "${OUTPUT_DIR}"
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "${VOLID}" \
    -eltorito-boot boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/grub/boot.cat \
    --grub2-boot-info \
    --grub2-mbr "${GRUB_I386_DIR}/boot_hybrid.img" \
    -eltorito-alt-boot \
        -e EFI/efiboot.img \
        -no-emul-boot \
    -append_partition 2 0xef "${ISO_DIR}/EFI/efiboot.img" \
    -output "${OUTPUT_DIR}/${ISO_NAME}" \
    "${ISO_DIR}"

# ---- Checksums ----
(cd "${OUTPUT_DIR}" && sha512sum "${ISO_NAME}" > SHA512SUMS)

echo "Created hybrid BIOS+EFI ISO: ${OUTPUT_DIR}/${ISO_NAME}"
