#!/bin/bash
# __BRAND_NAME__ disk layout (every target). Runs on the device, once, from
# __BRAND__-storage.service, early in the first boot: before the disks are
# mounted, journald writes to /var/log and Docker starts, so the folders it
# moves are not in use. Installed to /usr/lib/__BRAND__/ by
# install-firstboot.sh, which replaces the placeholders.
#
# Reads the "storage" key of the imager's __BRAND__-setup.json (format in
# firstboot-storage-check.sh; first boot's setup deletes the file later).
# Sizes the root partition, puts the rest of the disk in one LVM volume group
# named __BRAND__ (a volume can grow later with lvextend), and makes one ext4
# volume per folder, moving what the folder held onto it. A layout that does
# not fit, or an invalid key, leaves the disk as it is: first boot then grows
# the root over it, and the login screen says why. The outcome is kept in
# /var/lib/__BRAND__/storage-status.

SETUP_BRAND="${SETUP_BRAND:-__BRAND__}"
SETUP_ROOT="${SETUP_ROOT:-}"                    # tests write under a scratch root
STORAGE_SYS="${STORAGE_SYS:-/sys/class/block}"
STORAGE_DONE="/var/lib/${SETUP_BRAND}/.storage-done"
GIB=1073741824
MIB=1048576
STORAGE_SLACK=$(( 16 * MIB ))   # LVM metadata and extent rounding
STORAGE_TAIL=${MIB}             # the backup GPT at the end of the disk

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-setup-check.sh"   # SETUP_FILE, SETUP_MAX_BYTES
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-storage-check.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-disk.sh"

# storage_mount_opts <mount>: os-security's hardening for the folders it
# knows (packages/os-security/src/lib/filesystem.sh), and the same for logs
storage_mount_opts() {
    case "$1" in
        /var/log|/var/tmp) echo "noexec,nosuid,nodev" ;;
        /home|/srv|/opt) echo "nosuid,nodev" ;;
        *) echo "defaults" ;;
    esac
}

# storage_plan <file> <disk-bytes> <root-start-bytes> <root-bytes>: the
# layout, one line each: "root <bytes>", "pv <start-bytes>", then
# "lv <name> <mount> <GiB|rest> <options>" (the rest last). "skipped: <why>"
# when it does not fit; nothing when there is no root size.
storage_plan() {
    local disk="$2" root mount name size fixed=0 rest=0 pv needed lvs=""
    {
        read -r root
        while read -r mount size; do
            if [ "${size}" = rest ]; then rest=1; else fixed=$(( fixed + size )); fi
            name="${mount#/}"
            lvs+="lv ${name//\//-} ${mount} ${size} $(storage_mount_opts "${mount}")"$'\n'
        done
    } < <(jq -r '.storage | (.rootGiB // ""), ((.volumes // [])
        | (map(select(.sizeGiB != null)) + map(select(.sizeGiB == null)))[]
        | "\(.mount) \(.sizeGiB // "rest")")' "$1")
    [ -n "${root}" ] || return 0
    root=$(( root * GIB ))
    # never shrink the root; whole MiB, whatever the disk's sector size
    [ "${root}" -ge "$4" ] || root=$(( ($4 + MIB - 1) / MIB * MIB ))
    pv=$(( ($3 + root + MIB - 1) / MIB * MIB ))
    needed=$(( pv + (fixed + rest) * GIB + STORAGE_SLACK + STORAGE_TAIL ))
    if [ "${disk}" -lt "${needed}" ]; then
        echo "skipped: needs $(( (needed + 999999999) / 1000000000 )) GB, disk has $(( disk / 1000000000 )) GB"
        return 0
    fi
    printf 'root %s\npv %s\n%s' "${root}" "${pv}" "${lvs}"
}

# step <what> <command...>: run it; on failure remember what failed
STORAGE_FAILED=""
step() {
    local what="$1"
    shift
    "$@" || { STORAGE_FAILED="${what}"; echo "ERROR: disk layout: ${what} failed" >&2; return 1; }
}

# copy_folder <dir>: MOVE_FROM's content into <dir> (cp -a of "dir/." also
# carries the folder's owner and mode)
copy_folder() { cp -a "${MOVE_FROM}/." "$1/"; }

# move_into_volume <device> <dir> <options>: the folder's content onto the
# new volume, its fstab line (so a later failure never leaves it emptied
# and unmounted at the next boot), then the volume mounted in its place
move_into_volume() {
    MOVE_FROM="${SETUP_ROOT}$2"
    mkdir -p "${MOVE_FROM}" &&
    with_mount "$1" copy_folder &&
    echo "$1 $2 ext4 $3 0 2" >> "${SETUP_ROOT}/etc/fstab" &&
    find "${MOVE_FROM}" -mindepth 1 -delete &&
    mount -o "$3" "$1" "${MOVE_FROM}"
}

# make_partitions <disk> <root-partition-number> <root-device> <root-bytes> <pv-bytes>
make_partitions() {
    local disk="$1" part="$2"
    # A smaller image written to this disk left its backup GPT mid-disk
    if [ "$(blkid -o value -s PTTYPE "${disk}" 2>/dev/null)" = "gpt" ]; then
        step "moving the backup partition table" sfdisk --relocate gpt-bak-std "${disk}" < /dev/null || return 1
    fi
    step "resizing the root partition" sfdisk --no-reread -N "${part}" "${disk}" <<< ",$(( $4 / MIB ))MiB" &&
    step "adding the volume partition" sfdisk --no-reread --append "${disk}" <<< "$(( $5 / MIB ))MiB,,lvm" &&
    step "reading the partition table" partx -u --nr "${part}" "${disk}" &&
    step "reading the partition table" partx -a --nr "$(( part + 1 ))" "${disk}" &&
    step "growing the root filesystem" resize2fs "$3" &&
    { udevadm settle || true; }
}

fstab_header() { echo "# ${SETUP_BRAND} disk layout" >> "${SETUP_ROOT}/etc/fstab"; }

# build_storage <disk> <root-partition-number> <root-device> <plan>
build_storage() {
    local disk="$1" part="$2" kind root pv pv_dev name mount size opts dev size_args
    while read -r kind name _; do
        case "${kind}" in root) root="${name}" ;; pv) pv="${name}" ;; esac
    done <<< "$4"
    pv_dev="/dev/$(disk_partition "${disk#/dev/}" $(( part + 1 )))"
    make_partitions "${disk}" "${part}" "$3" "${root}" "${pv}" &&
    step pvcreate pvcreate -ff -y "${pv_dev}" &&
    step vgcreate vgcreate "${SETUP_BRAND}" "${pv_dev}" &&
    step "writing /etc/fstab" fstab_header || return 1
    while read -r _ name mount size opts; do
        dev="/dev/${SETUP_BRAND}/${name}"
        size_args=(-L "${size}G")
        [ "${size}" != rest ] || size_args=(-l 100%FREE)
        step "creating ${mount}" lvcreate -y -n "${name}" "${size_args[@]}" "${SETUP_BRAND}" &&
        { udevadm settle || true; } &&
        step "formatting ${mount}" mkfs.ext4 -q -L "${name}" "${dev}" &&
        step "moving ${mount}" move_into_volume "${dev}" "${mount}" "${opts}" || return 1
    done < <(grep '^lv ' <<< "$4")
}

# skip_storage <why>: leave the disk as it is, and say why
skip_storage() {
    echo "WARNING: disk layout skipped: $1" >&2
    record_state storage-status "skipped: $1"
}

# apply_storage_dir <mounted-boot-dir>
apply_storage_dir() {
    local f="$1/${SETUP_FILE}" problem root_dev disk part plan sys
    [ -f "${f}" ] && [ "$(wc -c < "${f}")" -le "${SETUP_MAX_BYTES}" ] || return 0
    # a broken file is first boot's setup's to report
    jq -e 'type == "object" and .version == 1 and .storage != null' "${f}" >/dev/null 2>&1 || return 0
    problem=$(validate_storage "${f}")
    [ -z "${problem}" ] || { skip_storage "${problem}"; return 0; }
    read -r root_dev disk < <(root_disk) || return 0
    part=$(partition_number "${root_dev}") || return 0
    sys="${STORAGE_SYS}/${root_dev#/dev/}"
    plan=$(storage_plan "${f}" "$(blockdev --getsize64 "/dev/${disk}")" \
        $(( $(cat "${sys}/start") * 512 )) $(( $(cat "${sys}/size") * 512 ))) || return 0
    case "${plan}" in
        "") return 0 ;;
        skipped:*) skip_storage "${plan#skipped: }"; return 0 ;;
    esac
    if ! build_storage "/dev/${disk}" "${part}" "${root_dev}" "${plan}"; then
        record_state storage-status "failed: ${STORAGE_FAILED}"
        return 1
    fi
    record_state storage-status "applied"
    echo "Disk layout applied."
}

# copy_setup_file <boot-dir>: the setup file to SETUP_COPY, so the boot
# partition is not held while the disk is laid out
copy_setup_file() {
    [ ! -f "$1/${SETUP_FILE}" ] || cp "$1/${SETUP_FILE}" "${SETUP_COPY}/"
}

# run_storage <done-flag>: once, whatever the outcome; marked done first, so
# a run cut off halfway is not repeated over a half-built layout (the login
# screen says it failed)
run_storage() {
    local dev status=0
    mkdir -p "$(dirname "$1")"
    touch "$1"
    dev=$(boot_partition) && is_fat_partition "${dev}" || return 0
    SETUP_COPY=$(mktemp -d) || return 1
    if with_mount "${dev}" copy_setup_file -t vfat -o ro,nosuid,nodev,noexec,umask=077; then
        apply_storage_dir "${SETUP_COPY}" || status=1
    fi
    rm -rf "${SETUP_COPY}"
    return "${status}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_storage "${SETUP_ROOT}${STORAGE_DONE}"
fi
