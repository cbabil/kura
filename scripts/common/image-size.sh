#!/bin/bash
# scripts/common/image-size.sh
# Checks that a rootfs fits its image partition before copying it, so a
# too-small OS_ROOTFS_SIZE fails early with a fix instead of midway through
# the copy with "No space left on device".
# Source this file; it defines functions only.

# check_rootfs_fits <used-bytes> <partition-bytes>
# Requires 10% headroom for ext4 metadata and the journal.
check_rootfs_fits() {
    local used="$1" partition="$2" mib=$((1024 * 1024)) gib=$((1024 * 1024 * 1024))
    local needed=$(( used * 110 / 100 ))
    [ "${needed}" -le "${partition}" ] && return 0
    echo "ERROR: rootfs is $(( used / mib )) MiB but the root partition is" \
         "$(( partition / mib )) MiB (10% headroom needed)." >&2
    echo "       Set OS_ROOTFS_SIZE=$(( (needed + gib - 1) / gib ))G in .env." >&2
    return 1
}
