#!/bin/bash
# scripts/common/firstboot-disk.sh
# Disk helpers for first boot (firstboot.sh, firstboot-setup.sh) and the PC
# installer: the root disk, the boot partition, mounting a partition for one
# step, wiping a file. Installed next
# to firstboot.sh by install-firstboot.sh. Defines functions only.

# root_disk: "<root-device> <parent-disk>"; fails when / is not on a disk
# partition (a live or container root)
root_disk() {
    local root_dev disk
    root_dev=$(findmnt -no SOURCE / 2>/dev/null) || return 1
    disk=$(lsblk -ndo PKNAME "${root_dev}" 2>/dev/null) || return 1
    [ -n "${disk}" ] || return 1
    echo "${root_dev} ${disk}"
}

# disk_partition <disk> <n>: partition <n>'s name (nvme0n1 -> nvme0n1p1,
# sda -> sda1)
disk_partition() {
    case "$1" in
        *[0-9]) echo "$1p$2" ;;
        *) echo "$1$2" ;;
    esac
}

# boot_partition: partition 1 of the root disk (the Pi's FAT boot partition)
boot_partition() {
    local disk
    disk=$(root_disk) || return 1
    echo "/dev/$(disk_partition "${disk#* }" 1)"
}

# wipe_file <file>: overwrite in place before deleting (best effort: the
# card's flash controller may still keep old copies)
wipe_file() {
    local size
    size=$(wc -c < "$1" | tr -d ' ')
    if [ "${size}" -gt 0 ]; then
        dd if=/dev/zero of="$1" bs="${size}" count=1 conv=notrunc 2>/dev/null || true
    fi
    sync
}

is_fat_partition() { [ -b "$1" ] && [ "$(blkid -o value -s TYPE "$1" 2>/dev/null)" = "vfat" ]; }

# with_mount <device> <function> <mount options...>: run <function> <dir> on
# the mounted device. Returns the function's status, 1 if unmounting fails,
# and 2 if the device does not mount.
with_mount() {
    local dev="$1" fn="$2" dir status=0
    shift 2
    dir=$(mktemp -d) || return 2
    if ! mount "$@" "${dev}" "${dir}" 2>/dev/null; then
        rmdir "${dir}" 2>/dev/null
        return 2
    fi
    "${fn}" "${dir}" || status=$?
    umount "${dir}" || status=1
    rmdir "${dir}" 2>/dev/null || true
    return "${status}"
}
