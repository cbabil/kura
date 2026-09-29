#!/bin/bash
# __BRAND_NAME__ first-boot setup (every target). Runs on the device, once,
# from __BRAND__-firstboot.service: after Docker, before tomod and the
# supervisor. Installed to /usr/lib/__BRAND__/firstboot.sh by
# scripts/common/install-firstboot.sh, which replaces the placeholders.
#
# Every step is safe to repeat. First boot is marked done only when all steps
# succeed, so a failure is retried on the next boot. SSH host keys are made
# by the separate __BRAND__-ssh-keygen.service, which must not wait for Docker.

FIRSTBOOT_DONE="/var/lib/__BRAND__/.firstboot-done"
IMAGES_DIR="/usr/share/__BRAND__/images"
TOMO_NETWORK="tomo_main"

# resize_root: grow the root partition and filesystem to fill the disk.
# The Pi image ships a small root partition; x86 disks vary. Skipped on the
# live ISO, whose root is not a partition.
resize_root() {
    local root_dev root_disk root_part
    root_dev=$(findmnt -no SOURCE / 2>/dev/null) || return 0
    root_disk=$(lsblk -ndo PKNAME "${root_dev}" 2>/dev/null) || return 0
    [ -n "${root_disk}" ] || return 0
    root_part=$(echo "${root_dev}" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)$/\1/p')
    [ -n "${root_part}" ] || return 0
    growpart "/dev/${root_disk}" "${root_part}" || true   # exits 1 if already full size
    resize2fs "${root_dev}"
}

# load_images <dir>: load container images saved at build time, so tomod
# starts without internet.
load_images() {
    local dir="$1" archive status=0
    [ -d "${dir}" ] || return 0
    for archive in "${dir}"/*.tar; do
        [ -e "${archive}" ] || continue
        if ! docker load -q -i "${archive}"; then
            echo "ERROR: could not load ${archive}" >&2
            status=1
        fi
    done
    return "${status}"
}

# ensure_network <name>: create the Docker network tomod expects.
ensure_network() {
    docker network inspect "$1" >/dev/null 2>&1 && return 0
    docker network create "$1" >/dev/null
}

# apply_cloud_hostname: set the hostname from cloud-init style user-data on
# an attached CD or disk (x86 VMs). No-op when there is none.
apply_cloud_hostname() {
    local dev dir name
    for dev in /dev/sr0 /dev/vdb; do
        [ -b "${dev}" ] || continue
        dir=$(mktemp -d)
        if mount -o ro "${dev}" "${dir}" 2>/dev/null; then
            if [ -f "${dir}/user-data" ]; then
                name=$(sed -n 's/^hostname:[[:space:]]*\([^[:space:]]*\).*/\1/p' \
                    "${dir}/user-data" | head -1)
                [ -n "${name}" ] && hostnamectl set-hostname "${name}"
            fi
            umount "${dir}"
        fi
        rmdir "${dir}" 2>/dev/null || true
    done
    return 0
}

# run_firstboot <done-flag> <images-dir>
run_firstboot() {
    local done_flag="$1" images="$2" status=0
    [ -f "${done_flag}" ] && return 0

    resize_root || { echo "WARNING: root partition resize failed" >&2; status=1; }
    load_images "${images}" || status=1
    ensure_network "${TOMO_NETWORK}" || { echo "ERROR: could not create ${TOMO_NETWORK}" >&2; status=1; }
    apply_cloud_hostname

    if [ "${status}" -ne 0 ]; then
        echo "First boot incomplete; it will be retried on the next boot." >&2
        return 1
    fi
    mkdir -p "$(dirname "${done_flag}")"
    touch "${done_flag}"
    echo "First boot complete."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_firstboot "${FIRSTBOOT_DONE}" "${IMAGES_DIR}"
fi
