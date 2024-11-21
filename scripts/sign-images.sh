#!/bin/bash
set -e

# Configuration
CERT_PATH="/etc/stratura/certs"
KEY_PATH="/etc/stratura/keys"
HSM_SLOT="0"
VERSION=$(cat VERSION)

# Function to sign with HSM
sign_with_hsm() {
    local file=$1
    local signature_file=$2
    pkcs11-tool --sign --slot ${HSM_SLOT} --input-file "$file" --output-file "$signature_file"
}

# Function to sign with regular key
sign_with_key() {
    local file=$1
    local signature_file=$2
    openssl dgst -sha256 -sign "${KEY_PATH}/signing-key.pem" -out "$signature_file" "$file"
}

# Sign bootloader
sign_bootloader() {
    local bootloader="tmp/deploy/images/raspberrypi5/u-boot.bin"
    if [ -f "$bootloader" ]; then
        sign_with_hsm "$bootloader" "$bootloader.sig"
    fi
}

# Sign kernel
sign_kernel() {
    local kernel="tmp/deploy/images/raspberrypi5/Image"
    if [ -f "$kernel" ]; then
        sign_with_hsm "$kernel" "$kernel.sig"
    fi
}

# Sign update bundle
sign_update_bundle() {
    local bundle="tmp/deploy/images/raspberrypi5/stratura-image-prod.raucb"
    if [ -f "$bundle" ]; then
        rauc sign --key "${KEY_PATH}/rauc.key.pem" \
                 --cert "${CERT_PATH}/rauc.cert.pem" \
                 "$bundle"
    fi
}

# Main signing process
main() {
    echo "Starting signing process for version ${VERSION}"
    
    # Create necessary directories
    mkdir -p "${CERT_PATH}" "${KEY_PATH}"
    
    # Sign components
    sign_bootloader
    sign_kernel
    sign_update_bundle
    
    # Generate checksums
    pushd tmp/deploy/images/raspberrypi5
    sha256sum * > SHA256SUMS
    gpg --detach-sign --armor SHA256SUMS
    popd
    
    echo "Signing complete"
}

main "$@" 