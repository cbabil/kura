#!/bin/bash
# scripts/common/disk-image.sh
# Steps shared by the disk image builders (scripts/rpi5/create-image.sh,
# scripts/x86_64/create-image.sh): a loop device over the image, one mount at
# a time, the rootfs copy, checksums, and cleanup on any exit. Root required.
# Source this file; it defines functions only.

DISK_IMAGE_LOOP=""
DISK_IMAGE_MNT=""

# disk_image_cleanup: unmount and detach whatever is still attached
disk_image_cleanup() {
    if [ -n "${DISK_IMAGE_MNT}" ]; then
        umount "${DISK_IMAGE_MNT}" 2>/dev/null || true
        rmdir "${DISK_IMAGE_MNT}" 2>/dev/null || true
        DISK_IMAGE_MNT=""
    fi
    if [ -n "${DISK_IMAGE_LOOP}" ]; then
        losetup -d "${DISK_IMAGE_LOOP}" 2>/dev/null || true
        DISK_IMAGE_LOOP=""
    fi
}

# disk_image_attach <img>: loop device with partitions (<loop>p1, p2...) in
# DISK_IMAGE_LOOP; cleaned up on exit
disk_image_attach() {
    modprobe loop 2>/dev/null || true
    trap disk_image_cleanup EXIT
    DISK_IMAGE_LOOP=$(losetup --show --partscan -f "$1")
}

# disk_image_mount <partition>: mounted on a new directory, DISK_IMAGE_MNT
disk_image_mount() {
    DISK_IMAGE_MNT=$(mktemp -d)
    mount "$1" "${DISK_IMAGE_MNT}"
}

disk_image_unmount() {
    umount "${DISK_IMAGE_MNT}"
    rmdir "${DISK_IMAGE_MNT}"
    DISK_IMAGE_MNT=""
}

# disk_image_copy_rootfs <rootfs> <partition>: owners by number (the build
# host's users differ from the image's), xattrs (file capabilities) and ACLs
disk_image_copy_rootfs() {
    local flags=(--numeric-owner --xattrs --xattrs-include='*' --acls)
    disk_image_mount "$2"
    echo "  Copying rootfs..."
    tar "${flags[@]}" -C "$1" -cf - . | tar "${flags[@]}" -C "${DISK_IMAGE_MNT}" -xpf -
    disk_image_unmount
}

# disk_image_finish <img>: detach, then write SHA512SUMS next to the image
disk_image_finish() {
    losetup -d "${DISK_IMAGE_LOOP}"
    DISK_IMAGE_LOOP=""
    (cd "$(dirname "$1")" && sha512sum "$(basename "$1")" > SHA512SUMS)
}
