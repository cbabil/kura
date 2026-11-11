#!/bin/bash
# scripts/rpi5/strip-rootfs.sh
# What shrinking the Pi image must not remove. The GPU firmware is on the boot
# partition, but the kernel loads the Wi-Fi firmware from /usr/lib/firmware.
#
# Source this file; it defines functions only.

# require_dm_mod <rootfs>: the Pi 5 kernel's (2712) device-mapper (dm-mod), which the
# disk layout's LVM volumes need, as a module or built in. The Pi boots
# without an initramfs; the root stays a plain partition, so LVM is only
# needed once the system runs.
require_dm_mod() {
    local mods
    for mods in "$1"/lib/modules/*-2712/; do
        grep -qs 'drivers/md/dm-mod.ko' "${mods}modules.builtin" && return 0
        [ -z "$(find "${mods}kernel/drivers/md" -name 'dm-mod.ko*' 2>/dev/null)" ] || return 0
    done
    echo "ERROR: no device-mapper (dm-mod) in the Pi kernel: disk layouts would fail" >&2
    return 1
}

# strip_firmware <rootfs>: everything but the Wi-Fi firmware (brcm, and cypress,
# which brcm links to) and the regulatory database. Fails if the firmware is
# missing: a Wi-Fi-only Pi would never reach the network.
strip_firmware() {
    local fw="$1/usr/lib/firmware"
    if [ ! -d "${fw}/brcm" ]; then
        echo "ERROR: no Wi-Fi firmware in ${fw}/brcm (firmware-brcm80211)" >&2
        return 1
    fi
    find "${fw}" -mindepth 1 -maxdepth 1 ! -name brcm ! -name cypress \
        ! -name 'regulatory.db*' -exec rm -rf {} +
}
