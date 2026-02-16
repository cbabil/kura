#!/bin/bash
# scripts/rpi5/customize-rootfs.sh
# RPi5-specific rootfs customization.
# RPi5-specific rootfs customizations applied during build
#
# Usage: customize-rootfs.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

echo "Applying RPi5-specific customization..."

# ---- Configure RPi APT repository ----
install -d "${ROOTFS}/etc/apt/sources.list.d"
cat > "${ROOTFS}/etc/apt/sources.list.d/raspi.list" <<'EOF'
deb http://archive.raspberrypi.com/debian/ trixie main
EOF

# Import RPi archive signing key for package verification
if [ -f "${ROOTFS}/usr/bin/gpg" ]; then
    curl -fsSL https://archive.raspberrypi.com/debian/pool/main/r/raspberrypi-archive-keyring/raspberrypi-archive-keyring_2021.1.1+rpt1_all.deb \
        -o /tmp/raspi-keyring.deb
    chroot "${ROOTFS}" dpkg -i /tmp/raspi-keyring.deb 2>/dev/null || true
    rm -f /tmp/raspi-keyring.deb
else
    echo "WARNING: gpg not available, skipping RPi signing key import"
fi

# NOTE: Docker is installed at first boot, not baked into the image.

# ---- Serial console on tty1 at 115200 ----
install -d "${ROOTFS}/etc/systemd/system/getty.target.wants"
mkdir -p "${ROOTFS}/etc/systemd/system/serial-getty@tty1.service.d"
cat > "${ROOTFS}/etc/systemd/system/serial-getty@tty1.service.d/override.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' 115200 %I $TERM
EOF

# ---- Strip unnecessary files to reduce image size ----
echo "Stripping docs/man/locales/firmware..."
rm -rf "${ROOTFS}/usr/share/doc"
rm -rf "${ROOTFS}/usr/share/man"
rm -rf "${ROOTFS}/usr/share/info"
# RPi firmware lives on the boot partition, not in /usr/lib/firmware
rm -rf "${ROOTFS}/usr/lib/firmware"
find "${ROOTFS}/usr/share/locale" -mindepth 1 -maxdepth 1 \
    ! -name 'C' ! -name 'en_US' -exec rm -rf {} + 2>/dev/null || true

# Strip i18n/translations
rm -rf "${ROOTFS}/usr/share/i18n/charmaps"
rm -rf "${ROOTFS}/usr/share/i18n/locales"
find "${ROOTFS}/usr/share/zoneinfo" -mindepth 1 -maxdepth 1 \
    -type d ! -name 'UTC' ! -name 'Etc' -exec rm -rf {} + 2>/dev/null || true

# Strip unused kernel modules (keep essential: fs, net, block, USB)
if [ -d "${ROOTFS}/lib/modules" ]; then
    KVER=$(ls "${ROOTFS}/lib/modules/" | head -1)
    if [ -n "${KVER}" ] && [ -d "${ROOTFS}/lib/modules/${KVER}/kernel" ]; then
        KMOD="${ROOTFS}/lib/modules/${KVER}/kernel"
        rm -rf "${KMOD}/sound"
        rm -rf "${KMOD}/drivers/media"
        rm -rf "${KMOD}/drivers/gpu"
        rm -rf "${KMOD}/drivers/bluetooth"
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

echo "RPi5 customization complete."
