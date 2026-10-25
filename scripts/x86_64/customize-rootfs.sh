#!/bin/bash
# scripts/x86_64/customize-rootfs.sh
# x86 PC rootfs customizations (target pc). The image runs on real hardware
# such as the Intel NUC, so firmware, kernel modules and time zones stay;
# only documentation and translations are removed.
#
# Usage: customize-rootfs.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

echo "Applying x86_64-specific customization..."

# ---- QEMU guest agent (Proxmox/KVM integration) ----
install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/qemu-guest-agent.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"

# ---- Serial console (VMs and the CI boot test) ----
install -d "${ROOTFS}/etc/systemd/system/getty.target.wants"
ln -sf /usr/lib/systemd/system/serial-getty@.service \
    "${ROOTFS}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# ---- Strip documentation and translations ----
echo "Stripping docs/man/locales..."
rm -rf "${ROOTFS}/usr/share/doc" "${ROOTFS}/usr/share/man" "${ROOTFS}/usr/share/info"
if [ -d "${ROOTFS}/usr/share/locale" ]; then
    find "${ROOTFS}/usr/share/locale" -mindepth 1 -maxdepth 1 \
        ! -name 'C' ! -name 'en_US' -exec rm -rf {} + 2>/dev/null || true
fi
rm -rf "${ROOTFS}/usr/share/i18n/charmaps" "${ROOTFS}/usr/share/i18n/locales"

echo "x86_64 customization complete."
