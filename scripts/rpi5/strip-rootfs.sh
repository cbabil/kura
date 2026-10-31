#!/bin/bash
# scripts/rpi5/strip-rootfs.sh
# What shrinking the Pi image must not remove. The GPU firmware is on the boot
# partition, but the kernel loads the Wi-Fi firmware from /usr/lib/firmware.
#
# Source this file; it defines functions only.

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
