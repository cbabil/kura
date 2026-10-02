#!/bin/bash
# scripts/common/systemd-units.sh
# Enables systemd units in an image rootfs without a running systemd.
# Source this file; it defines functions only.

# enable_unit <rootfs> <target> <unit-path>
# Creates the <target>.wants link, as `systemctl enable` would. Package
# postinst scripts normally do this; setting links explicitly means the image
# never depends on their behaviour inside a chroot. The link target is an
# absolute path inside the image (e.g. /usr/lib/systemd/system/x.service).
enable_unit() {
    local wants="$1/etc/systemd/system/$2.wants"
    install -d "${wants}"
    ln -sf "$3" "${wants}/$(basename "$3")"
}
