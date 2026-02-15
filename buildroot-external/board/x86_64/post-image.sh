#!/bin/bash
# x86_64 post-image script
# Prepares files for ISO creation (done by build.sh iso)

set -e

BOARD_DIR="$(dirname $0)"

# Single source of truth for default brand values
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/common/brand-defaults.sh"

OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"

echo "${OS_NAME} x86_64: Running post-image processing..."

# Setup EFI boot files for ISO creation
EFI_BOOT_DIR="${BINARIES_DIR}/EFI/BOOT"
mkdir -p "${EFI_BOOT_DIR}"

BOOTX64_FOUND=0

# Check standard Buildroot GRUB2 EFI output location
if [ -f "${BINARIES_DIR}/efi-part/EFI/BOOT/bootx64.efi" ]; then
    cp -a "${BINARIES_DIR}/efi-part/EFI/BOOT/"* "${EFI_BOOT_DIR}/"
    echo "${OS_NAME} x86_64: Copied EFI boot files from efi-part/"
    BOOTX64_FOUND=1
fi

# Check for standalone GRUB EFI binary
if [ "$BOOTX64_FOUND" -eq 0 ] && [ -f "${BINARIES_DIR}/grub-efi-bootx64.efi" ]; then
    cp "${BINARIES_DIR}/grub-efi-bootx64.efi" "${EFI_BOOT_DIR}/bootx64.efi"
    BOOTX64_FOUND=1
fi

# Check for grubx64.efi (alternative naming)
if [ "$BOOTX64_FOUND" -eq 0 ] && [ -f "${BINARIES_DIR}/grubx64.efi" ]; then
    cp "${BINARIES_DIR}/grubx64.efi" "${EFI_BOOT_DIR}/bootx64.efi"
    BOOTX64_FOUND=1
fi

# Check in efi-part root
if [ "$BOOTX64_FOUND" -eq 0 ] && [ -f "${BINARIES_DIR}/efi-part/bootx64.efi" ]; then
    cp "${BINARIES_DIR}/efi-part/bootx64.efi" "${EFI_BOOT_DIR}/bootx64.efi"
    BOOTX64_FOUND=1
fi

# If still not found, try to find any bootx64.efi
if [ "$BOOTX64_FOUND" -eq 0 ]; then
    FOUND_EFI=$(find "${BINARIES_DIR}" -name "bootx64.efi" -o -name "BOOTX64.EFI" 2>/dev/null | head -1)
    if [ -n "$FOUND_EFI" ]; then
        cp "$FOUND_EFI" "${EFI_BOOT_DIR}/bootx64.efi"
        BOOTX64_FOUND=1
    fi
fi

if [ "$BOOTX64_FOUND" -eq 0 ]; then
    echo "WARNING: GRUB2 EFI bootloader not found - ISO may not boot in EFI mode"
fi

# Create GRUB config for ISO boot (uses DEFAULT_NAME as template, sed replaces with OS_NAME)
cat > "${EFI_BOOT_DIR}/grub.cfg" << 'EOF'
set timeout=3
set default=0

insmod part_gpt
insmod ext2
insmod iso9660

menuentry "FalkenOS" {
    linux /boot/bzImage root=/dev/sr0 rootfstype=iso9660 console=tty0 console=ttyS0,115200n8
}

menuentry "FalkenOS (Serial Console)" {
    linux /boot/bzImage root=/dev/sr0 rootfstype=iso9660 console=ttyS0,115200n8
}
EOF
sed -i "s/${DEFAULT_NAME}/${OS_NAME}/g" "${EFI_BOOT_DIR}/grub.cfg"
echo "${OS_NAME} x86_64: Created GRUB configuration for ISO"

# Create version file
cat > ${BINARIES_DIR}/version.txt << EOF
${OS_NAME} Build Information
============================
Version: ${OS_VERSION:-1.0}
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Host: $(hostname)
Target: x86_64
EOF

echo "${OS_NAME} x86_64: Post-image processing complete"
echo "Run './build.sh iso' to create the ISO file"
echo "Run './build.sh docker' to create the Docker image"
