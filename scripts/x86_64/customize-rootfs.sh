#!/bin/bash
# scripts/x86_64/customize-rootfs.sh
# x86_64-specific rootfs customization.
# x86_64-specific rootfs customizations applied during build
#
# Usage: customize-rootfs.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

# shellcheck disable=SC1091
source "$(dirname "$0")/../common/systemd-units.sh"

echo "Applying x86_64-specific customization..."

# ---- Container storage in RAM on the live ISO ----
# The live root is an overlay (squashfs + RAM). containerd and Docker store
# images as overlays too, and the kernel refuses an overlay on an overlay, so
# no container can be created. On a live boot, their storage gets its own
# tmpfs (lost at reboot, like everything on the live ISO).
install -d "${ROOTFS}/usr/lib/systemd/system"
for dir in containerd docker; do
    cat > "${ROOTFS}/usr/lib/systemd/system/var-lib-${dir}.mount" <<UNITEOF
[Unit]
Description=${dir} storage in RAM (live system)
ConditionKernelCommandLine=boot=live
Before=containerd.service docker.service

[Mount]
What=tmpfs
Where=/var/lib/${dir}
Type=tmpfs
Options=mode=0711

[Install]
WantedBy=local-fs.target
UNITEOF
    enable_unit "${ROOTFS}" local-fs.target "/usr/lib/systemd/system/var-lib-${dir}.mount"
done

# ---- QEMU guest agent (Proxmox/KVM integration) ----
install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/qemu-guest-agent.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"

# ---- Serial console ----
install -d "${ROOTFS}/etc/systemd/system/getty.target.wants"
ln -sf /usr/lib/systemd/system/serial-getty@.service \
    "${ROOTFS}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# ---- Strip unnecessary files to reduce ISO size ----
echo "Stripping docs/man/locales/firmware..."
rm -rf "${ROOTFS}/usr/share/doc"
rm -rf "${ROOTFS}/usr/share/man"
rm -rf "${ROOTFS}/usr/share/info"
rm -rf "${ROOTFS}/usr/lib/firmware"
find "${ROOTFS}/usr/share/locale" -mindepth 1 -maxdepth 1 \
    ! -name 'C' ! -name 'en_US' -exec rm -rf {} + 2>/dev/null || true

# Strip i18n/translations
rm -rf "${ROOTFS}/usr/share/i18n/charmaps"
rm -rf "${ROOTFS}/usr/share/i18n/locales"
find "${ROOTFS}/usr/share/zoneinfo" -mindepth 1 -maxdepth 1 \
    -type d ! -name 'UTC' ! -name 'Etc' -exec rm -rf {} + 2>/dev/null || true

# Strip unused kernel modules (keep essential: fs, net, virtio, block)
if [ -d "${ROOTFS}/lib/modules" ]; then
    KVER=$(ls "${ROOTFS}/lib/modules/" | head -1)
    if [ -n "${KVER}" ] && [ -d "${ROOTFS}/lib/modules/${KVER}/kernel" ]; then
        KMOD="${ROOTFS}/lib/modules/${KVER}/kernel"
        rm -rf "${KMOD}/sound"
        rm -rf "${KMOD}/drivers/media"
        rm -rf "${KMOD}/drivers/gpu"
        rm -rf "${KMOD}/drivers/infiniband"
        rm -rf "${KMOD}/drivers/staging"
        rm -rf "${KMOD}/drivers/usb/serial"
        rm -rf "${KMOD}/drivers/bluetooth"
        rm -rf "${KMOD}/drivers/isdn"
        rm -rf "${KMOD}/drivers/nfc"
        rm -rf "${KMOD}/drivers/thunderbolt"
        rm -rf "${KMOD}/drivers/hwmon"
        rm -rf "${KMOD}/drivers/iio"
        rm -rf "${KMOD}/drivers/input/joystick"
        rm -rf "${KMOD}/drivers/input/touchscreen"
        rm -rf "${KMOD}/drivers/leds"
        # Regenerate module dependencies
        if [ -x "${ROOTFS}/sbin/depmod" ]; then
            chroot "${ROOTFS}" depmod "${KVER}" 2>/dev/null || true
        fi
    fi
fi

echo "x86_64 customization complete."
