#!/bin/bash
# scripts/common/apt-components.sh
# APT source changes shared by the targets' configure-repos.sh.
# Source this file; it defines functions only.

# add_non_free_firmware <rootfs>: Debian's non-free-firmware component, for
# Wi-Fi, GPU and CPU firmware. Handles DEB822 .sources and sources.list.
add_non_free_firmware() {
    local rootfs="$1"
    if [ -f "${rootfs}/etc/apt/sources.list.d/debian.sources" ]; then
        sed -i.orig 's|^Components: main$|Components: main non-free-firmware|' \
            "${rootfs}/etc/apt/sources.list.d/debian.sources"
        rm -f "${rootfs}/etc/apt/sources.list.d/debian.sources.orig"
    elif [ -f "${rootfs}/etc/apt/sources.list" ]; then
        sed -i.orig 's|^\(deb .* trixie main\)$|\1 non-free-firmware|' "${rootfs}/etc/apt/sources.list"
        rm -f "${rootfs}/etc/apt/sources.list.orig"
    fi
}
