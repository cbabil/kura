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
# named __BRAND__ (a volume can grow later with lvextend), makes one ext4
# volume per folder holding a copy of what the folder held, plus an optional
# swap volume, writes their fstab lines, and restarts. The folders move across
# the restart, so nothing that runs early in this boot (and might write under
# /var) can be caught halfway: the next boot mounts the volumes from fstab
# before anything uses them, and "finish" (__BRAND__-storage-finish.service)
# then clears the root's old copies, which the volumes cover. A layout that does
# not fit, or an invalid key, leaves the disk as it is: first boot then grows
# the root over it, and the login screen says why. The outcome is kept in
# /var/lib/__BRAND__/storage-status.

SETUP_BRAND="${SETUP_BRAND:-__BRAND__}"
SETUP_ROOT="${SETUP_ROOT:-}"                    # tests write under a scratch root
STORAGE_SYS="${STORAGE_SYS:-/sys/class/block}"
STORAGE_DONE="/var/lib/${SETUP_BRAND}/.storage-done"
STORAGE_PENDING="/var/lib/${SETUP_BRAND}/.storage-pending"   # built, restart to use
# This boot built the layout (gone at the restart: /run is a RAM disk): the
# finishing step, which the pending flag would start, waits for the next boot
STORAGE_BUILT="/run/${SETUP_BRAND}-storage-built"
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

# storage_mount_opts <mount>: noexec for scratch and log folders (as
# os-security hardens /tmp and /var/tmp), the defaults for the rest of /var,
# where dpkg, Docker and other services run programs and keep device nodes,
# and nosuid,nodev for every other folder (/home, /srv, /opt, the user's own).
# /tmp as a volume: its fstab line makes the next boot mount it instead of
# the RAM disk (the fstab generator's tmp.mount overrides Debian's).
storage_mount_opts() {
    case "$1" in
        /tmp|/var/log|/var/tmp) echo "noexec,nosuid,nodev" ;;
        /var|/var/*) echo "defaults" ;;
        *) echo "nosuid,nodev" ;;
    esac
}

# storage_plan <file> <disk-bytes> <root-start-bytes> <root-bytes>: the
# layout, one line each: "root <bytes>", "pv <start-bytes>", "swap <GiB>" if
# asked for, then "lv <name> <mount> <GiB|rest> <options>", parents before the
# folders under them. "skipped: <why>" when it does not fit; nothing when
# there is no root size.
storage_plan() {
    local disk="$2" root swap name mount size fixed=0 rest=0 pv needed lvs=""
    {
        read -r root
        read -r swap
        while read -r name mount size; do
            if [ "${size}" = rest ]; then rest=1; else fixed=$(( fixed + size )); fi
            lvs+="lv ${name} ${mount} ${size} $(storage_mount_opts "${mount}")"$'\n'
        done
    } < <(jq -r "${STORAGE_JQ_DEFS}"'.storage | (.rootGiB // ""), (.swapGiB // ""), ((.volumes // [])
        | sort_by(.mount | split("/") | length)[]
        | "\(.mount | lv_name) \(.mount) \(.sizeGiB // "rest")")' "$1")
    [ -n "${root}" ] || return 0
    root=$(( root * GIB ))
    # never shrink the root; whole MiB, whatever the disk's sector size
    [ "${root}" -ge "$4" ] || root=$(( ($4 + MIB - 1) / MIB * MIB ))
    pv=$(( ($3 + root + MIB - 1) / MIB * MIB ))
    needed=$(( pv + (fixed + rest + ${swap:-0}) * GIB + STORAGE_SLACK + STORAGE_TAIL ))
    if [ "${disk}" -lt "${needed}" ]; then
        echo "skipped: needs $(( (needed + 999999999) / 1000000000 )) GB, disk has $(( disk / 1000000000 )) GB"
        return 0
    fi
    printf 'root %s\npv %s\n%s%s' "${root}" "${pv}" "${swap:+swap ${swap}$'\n'}" "${lvs}"
}

# step <what> <command...>: run it; on failure remember what failed
STORAGE_FAILED=""
step() {
    local what="$1"
    shift
    "$@" || { STORAGE_FAILED="${what}"; echo "ERROR: disk layout: ${what} failed" >&2; return 1; }
}

# fstab_add <line...>: appended to the system's fstab, one line each
fstab_add() { printf '%s\n' "$@" >> "${SETUP_ROOT}/etc/fstab"; }

# prune_nested <copy> <mount>: in a folder's copy, empty the folders under it
# that get volumes of their own (STORAGE_MOUNTS), so each byte is on one
# volume; the folders stay as their mount points
prune_nested() {
    local other
    for other in "${STORAGE_MOUNTS[@]}"; do
        [[ "${other}" == "$2"/* ]] || continue
        [ ! -d "$1${other#"$2"}" ] || find "$1${other#"$2"}" -xdev -mindepth 1 -delete || return 1
    done
}

# copy_folder <dir>: MOVE_FROM's content into <dir> (cp -a of "dir/." also
# carries the folder's owner and mode; -x never copies another filesystem)
copy_folder() { cp -ax "${MOVE_FROM}/." "$1/" && prune_nested "$1" "${MOVE_MOUNT}"; }

# fill_volume <device> <dir>: a copy of the folder on its volume; the
# folder itself stays as it is until the restart
fill_volume() {
    MOVE_FROM="${SETUP_ROOT}$2" MOVE_MOUNT="$2"
    mkdir -p "${MOVE_FROM}" && with_mount "$1" copy_folder
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

fstab_header() { fstab_add "# ${SETUP_BRAND} disk layout"; }

# create_volume <name> <GiB|rest>: the rest takes what the others left
create_volume() {
    local size_args=(-L "$2G")
    [ "$2" != rest ] || size_args=(-l 100%FREE)
    step "creating the $1 volume" lvcreate -y -n "$1" "${size_args[@]}" "${SETUP_BRAND}"
}

# build_storage <disk> <root-partition-number> <root-device> <plan>: every
# volume first (the one taking the rest last), then each folder copied onto
# its volume, then every fstab line at once: a failure on the way leaves
# fstab as it was, and the next boot as this one
build_storage() {
    local disk="$1" part="$2" kind root pv swap pv_dev name mount size opts line lvs=() lines=()
    while read -r kind name _; do
        case "${kind}" in root) root="${name}" ;; pv) pv="${name}" ;; swap) swap="${name}" ;; esac
    done <<< "$4"
    while IFS= read -r line; do lvs+=("${line}"); done < <(grep '^lv ' <<< "$4")
    STORAGE_MOUNTS=()
    for line in "${lvs[@]}"; do read -r _ _ mount _ <<< "${line}"; STORAGE_MOUNTS+=("${mount}"); done
    pv_dev="/dev/$(disk_partition "${disk#/dev/}" $(( part + 1 )))"
    make_partitions "${disk}" "${part}" "$3" "${root}" "${pv}" &&
    step pvcreate pvcreate -ff -y "${pv_dev}" &&
    step vgcreate vgcreate "${SETUP_BRAND}" "${pv_dev}" || return 1
    while read -r name size; do
        create_volume "${name}" "${size}" || return 1
    done < <([ -z "${swap}" ] || echo "swap ${swap}"
             printf '%s\n' "${lvs[@]}" | awk '$4 != "rest" {print $2, $4}'
             printf '%s\n' "${lvs[@]}" | awk '$4 == "rest" {print $2, $4}')
    udevadm settle || true
    lines=("# ${SETUP_BRAND} disk layout")
    if [ -n "${swap}" ]; then
        step "formatting swap" mkswap -L swap "/dev/${SETUP_BRAND}/swap" || return 1
        lines+=("/dev/${SETUP_BRAND}/swap none swap sw 0 0")
    fi
    for line in "${lvs[@]}"; do
        read -r _ name mount _ opts <<< "${line}"
        step "formatting ${mount}" mkfs.ext4 -q -L "${name:0:16}" "/dev/${SETUP_BRAND}/${name}" &&
        step "copying ${mount}" fill_volume "/dev/${SETUP_BRAND}/${name}" "${mount}" || return 1
        lines+=("/dev/${SETUP_BRAND}/${name} ${mount} ext4 ${opts} 0 2")
    done
    step "writing /etc/fstab" fstab_add "${lines[@]}"
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
    install -d "${SETUP_ROOT}/run" && touch "${SETUP_ROOT}${STORAGE_BUILT}" || return 1
    # before the copies, so the volume holding /var/lib carries it too
    install -d "$(dirname "${SETUP_ROOT}${STORAGE_PENDING}")" && touch "${SETUP_ROOT}${STORAGE_PENDING}" || return 1
    if ! build_storage "/dev/${disk}" "${part}" "${root_dev}" "${plan}"; then
        rm -f "${SETUP_ROOT}${STORAGE_PENDING}"
        record_state storage-status "failed: ${STORAGE_FAILED}"
        return 1
    fi
    record_state storage-status "restarting"
    echo "Disk layout built; restarting to use it."
    # this boot's messages to the root's /var/log, kept by the next boot
    journalctl --flush || true
    systemctl --no-block reboot
}

# covered_folders: the folders the layout's fstab lines put on volumes
covered_folders() {
    awk -v h="# ${SETUP_BRAND} disk layout" '$0 == h {f = 1; next} f && $3 == "ext4" {print $2}' \
        "${SETUP_ROOT}/etc/fstab"
}

# keep_first_journal <root-view>: the journal the first boot flushed to the
# root's /var/log, kept next to this boot's on the volume now holding it
keep_first_journal() {
    local f id
    for f in "$1"/var/log/journal/*/*.journal; do
        [ -f "${f}" ] || continue
        id=$(basename "$(dirname "${f}")")
        mkdir -p "${SETUP_ROOT}/var/log/journal/${id}" &&
        cp -a "${f}" "${SETUP_ROOT}/var/log/journal/${id}/layout-first-$(basename "${f/system/boot}")" || return 1
    done
}

# clear_covered <root-view>: under the bind-mounted root, empty each folder
# whose volume is mounted on it; one that is not keeps its folder
clear_covered() {
    local mount
    while read -r mount; do
        if ! mountpoint -q "${SETUP_ROOT}${mount}"; then
            STORAGE_FAILED="${STORAGE_FAILED:-mounting ${mount}}"
            continue
        fi
        [ ! -d "$1${mount}" ] || find "$1${mount}" -xdev -mindepth 1 -delete ||
            : "${STORAGE_FAILED:=clearing the old ${mount} on the root}"
    done < <(covered_folders)
}

# finish_private: finish_storage in a mount namespace of its own, with
# private propagation. Its view of the root is a bind mount of /; in the
# system's namespace a mount made meanwhile (the EFI partition is nofail, so
# it is not waited for) would appear inside the view and hold it, and
# unmounting it there would unmount the real one.
finish_private() {
    if [ -z "${STORAGE_PRIVATE:-}" ] && command -v unshare >/dev/null 2>&1; then
        STORAGE_PRIVATE=1 exec unshare --mount --propagation private "$0" finish
    fi
    finish_storage
}

# finish_storage: the next boot, the volumes mounted: the root's old copies
# of their folders are cleared (seen through a bind mount of /, which shows
# the root without what is mounted on it). First boot's setup waits for this;
# a failure is recorded for the login screen and does not stop it.
finish_storage() {
    local view
    [ ! -e "${SETUP_ROOT}${STORAGE_BUILT}" ] || return 0   # the restart comes first
    STORAGE_FAILED=""
    if view=$(mktemp -d) && mount --bind "${SETUP_ROOT:-/}" "${view}"; then
        if covered_folders | grep -qxE '/var|/var/log'; then
            keep_first_journal "${view}" || echo "WARNING: the first boot's journal was not kept" >&2
        fi
        clear_covered "${view}"
        # The view is this namespace's own (see below); one that will not
        # unmount goes with the namespace, and the layout is in place either way
        umount "${view}" 2>/dev/null || umount -l "${view}" 2>/dev/null ||
            echo "WARNING: the view of the root stays mounted until this step ends" >&2
    else
        STORAGE_FAILED="seeing the root under the volumes"
    fi
    [ -z "${view}" ] || rmdir "${view}" 2>/dev/null || true
    rm -f "${SETUP_ROOT}${STORAGE_PENDING}"
    if [ -n "${STORAGE_FAILED}" ]; then
        echo "ERROR: disk layout: ${STORAGE_FAILED} failed" >&2
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
    if [ "${1:-}" = finish ]; then finish_private; else run_storage "${SETUP_ROOT}${STORAGE_DONE}"; fi
fi
