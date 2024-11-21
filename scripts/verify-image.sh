#!/bin/bash
set -e

# Configuration
CERT_PATH="/etc/stratura/certs"
VERSION=$(cat VERSION)

# Function to verify signature
verify_signature() {
    local file=$1
    local signature=$2
    local cert=$3
    openssl dgst -sha256 -verify "$cert" -signature "$signature" "$file"
}

# Verify bootloader
verify_bootloader() {
    local bootloader="tmp/deploy/images/raspberrypi5/u-boot.bin"
    if [ -f "$bootloader" ] && [ -f "$bootloader.sig" ]; then
        verify_signature "$bootloader" "$bootloader.sig" "${CERT_PATH}/boot.cert.pem"
    fi
}

# Verify kernel
verify_kernel() {
    local kernel="tmp/deploy/images/raspberrypi5/Image"
    if [ -f "$kernel" ] && [ -f "$kernel.sig" ]; then
        verify_signature "$kernel" "$kernel.sig" "${CERT_PATH}/kernel.cert.pem"
    fi
}

# Verify update bundle
verify_update_bundle() {
    local bundle="tmp/deploy/images/raspberrypi5/stratura-image-prod.raucb"
    if [ -f "$bundle" ]; then
        rauc verify "$bundle"
    fi
}

# Verify system integrity
verify_system_integrity() {
    # Verify partition table
    sfdisk -l /dev/mmcblk0
    
    # Verify filesystems
    fsck.ext4 -n /dev/mmcblk0p2  # Root A
    fsck.ext4 -n /dev/mmcblk0p3  # Root B
    fsck.ext4 -n /dev/mmcblk0p5  # State
    fsck.ext4 -n /dev/mmcblk0p6  # Data
}

# Main verification process
main() {
    echo "Starting verification process for version ${VERSION}"
    
    # Verify components
    verify_bootloader
    verify_kernel
    verify_update_bundle
    verify_system_integrity
    
    # Verify checksums
    pushd tmp/deploy/images/raspberrypi5
    sha256sum -c SHA256SUMS
    gpg --verify SHA256SUMS.asc SHA256SUMS
    popd
    
    echo "Verification complete"
}

main "$@" 