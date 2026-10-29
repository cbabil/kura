#!/bin/bash
# __BRAND_NAME__ first-boot setup (every target). Runs on the device, once,
# from __BRAND__-firstboot.service. Installed to /usr/lib/__BRAND__/firstboot.sh by
# scripts/common/install-firstboot.sh, which replaces the placeholders.
#
# Every step is safe to repeat. First boot is marked done only when all steps
# succeed, so a failure is retried on the next boot. SSH host keys are made
# by the separate __BRAND__-ssh-keygen.service.

FIRSTBOOT_DONE="/var/lib/__BRAND__/.firstboot-done"

# apply_setup (settings an imager left on the boot partition), setup_hostname,
# HOST_RE; root_disk and with_mount (firstboot-disk.sh, sourced by it)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-setup.sh"

# resize_root: grow the root partition and filesystem to fill the disk.
# The Pi image ships a small root partition; x86 disks vary. Skipped on the
# live or container systems, whose root is not a partition.
resize_root() {
    local root_dev root_disk root_part
    read -r root_dev root_disk < <(root_disk) || return 0
    root_part=$(echo "${root_dev}" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)$/\1/p')
    [ -n "${root_part}" ] || return 0
    growpart "/dev/${root_disk}" "${root_part}" || true   # exits 1 if already full size
    resize2fs "${root_dev}"
}

# cloud_hostname_from <dir>: the user-data hostname, if valid, for os-config
cloud_hostname_from() {
    local name
    [ -f "$1/user-data" ] || return 0
    name=$(sed -n 's/^hostname:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$1/user-data" | head -1)
    if [ -n "${name}" ] && [[ "${name}" =~ ${HOST_RE} ]]; then
        setup_hostname "${name}"
    fi
    return 0
}

# apply_cloud_hostname: set the hostname from cloud-init style user-data on
# an attached CD or disk (x86 VMs). No-op when there is none.
apply_cloud_hostname() {
    local dev
    for dev in /dev/sr0 /dev/vdb; do
        [ -b "${dev}" ] || continue
        with_mount "${dev}" cloud_hostname_from -o ro || true
    done
    return 0
}

# run_firstboot <done-flag>
run_firstboot() {
    local done_flag="$1" status=0
    [ -f "${done_flag}" ] && return 0

    apply_setup || status=1
    # after the setup file, whose password would replace it
    replace_default_password || status=1
    resize_root || { echo "WARNING: root partition resize failed" >&2; status=1; }
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
    run_firstboot "${FIRSTBOOT_DONE}"
fi
