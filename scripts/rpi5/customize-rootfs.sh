#!/bin/bash
# scripts/rpi5/customize-rootfs.sh
# RPi5-specific rootfs customization.
# Adapted from buildroot-external/board/straturaos/post-build.sh
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

# Import RPi GPG key (if available in overlay or fetch at build time)
# TODO: Add RPi archive signing key to rootfs

# ---- Enable Docker + containerd ----
install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/docker.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/docker.service"
ln -sf /usr/lib/systemd/system/containerd.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/containerd.service"

# ---- Serial console on tty1 at 115200 ----
install -d "${ROOTFS}/etc/systemd/system/getty.target.wants"
mkdir -p "${ROOTFS}/etc/systemd/system/serial-getty@tty1.service.d"
cat > "${ROOTFS}/etc/systemd/system/serial-getty@tty1.service.d/override.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' 115200 %I $TERM
EOF

echo "RPi5 customization complete."
