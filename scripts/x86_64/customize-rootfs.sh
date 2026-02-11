#!/bin/bash
# scripts/x86_64/customize-rootfs.sh
# x86_64-specific rootfs customization.
# Adapted from buildroot-external/board/straturaos-x86_64/post-build.sh
#
# Usage: customize-rootfs.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

echo "Applying x86_64-specific customization..."

# ---- Serial console ----
install -d "${ROOTFS}/etc/systemd/system/getty.target.wants"
ln -sf /usr/lib/systemd/system/serial-getty@.service \
    "${ROOTFS}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# ---- Docker group (GID 998, no Docker installed yet) ----
if ! grep -q '^docker:' "${ROOTFS}/etc/group" 2>/dev/null; then
    echo "docker:x:998:" >> "${ROOTFS}/etc/group"
fi

# Docker note: docker.io is in Trixie main (default sources).
# It will be installed by firstboot service on first network-connected boot.

# ---- Firstboot service ----
install -d "${ROOTFS}/usr/lib/straturaos"
cat > "${ROOTFS}/usr/lib/straturaos/firstboot.sh" <<'FBEOF'
#!/bin/bash
# StraturaOS first-boot script (x86_64 ISO target)
# Installs Docker, resizes root partition, generates SSH keys.

set -euo pipefail

FIRSTBOOT_FLAG="/var/lib/straturaos/.firstboot-done"
[ -f "${FIRSTBOOT_FLAG}" ] && exit 0

echo "StraturaOS: Running first-boot setup..."

# ---- Resize root partition ----
ROOT_DEV=$(findmnt -no SOURCE /)
ROOT_DISK=$(lsblk -ndo PKNAME "${ROOT_DEV}" 2>/dev/null || true)
if [ -n "${ROOT_DISK}" ]; then
    ROOT_PART=$(echo "${ROOT_DEV}" | grep -oP '\d+$' || true)
    if [ -n "${ROOT_PART}" ]; then
        growpart "/dev/${ROOT_DISK}" "${ROOT_PART}" 2>/dev/null || true
        resize2fs "${ROOT_DEV}" 2>/dev/null || true
    fi
fi

# ---- Generate SSH host keys ----
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# ---- Cloud-init user-data (if available) ----
for dev in /dev/sr0 /dev/vdb; do
    if [ -b "${dev}" ]; then
        MOUNT_DIR=$(mktemp -d)
        if mount -o ro "${dev}" "${MOUNT_DIR}" 2>/dev/null; then
            if [ -f "${MOUNT_DIR}/user-data" ]; then
                # Parse hostname from user-data
                NEW_HOSTNAME=$(grep -oP '^hostname:\s*\K\S+' "${MOUNT_DIR}/user-data" || true)
                if [ -n "${NEW_HOSTNAME}" ]; then
                    hostnamectl set-hostname "${NEW_HOSTNAME}"
                fi
            fi
            umount "${MOUNT_DIR}"
        fi
        rmdir "${MOUNT_DIR}" 2>/dev/null || true
    fi
done

# ---- Wait for network ----
echo "StraturaOS: Waiting for network (up to 60s)..."
NETWORK_UP=false
for i in $(seq 1 30); do
    if ping -c1 -W2 deb.debian.org >/dev/null 2>&1; then
        NETWORK_UP=true
        break
    fi
    sleep 2
done

# ---- Install Docker (requires network) ----
if [ "${NETWORK_UP}" = "true" ]; then
    echo "StraturaOS: Installing Docker..."
    apt-get update -qq
    apt-get install -y --no-install-recommends docker.io containerd
    systemctl enable --now docker
    echo "StraturaOS: Docker installed successfully."
else
    echo "StraturaOS: WARNING - No network. Docker not installed."
    echo "StraturaOS: Run 'apt-get update && apt-get install -y docker.io containerd' manually."
fi

# ---- Mark firstboot complete ----
mkdir -p "$(dirname "${FIRSTBOOT_FLAG}")"
touch "${FIRSTBOOT_FLAG}"
echo "StraturaOS: First-boot setup complete."
FBEOF
chmod 755 "${ROOTFS}/usr/lib/straturaos/firstboot.sh"

# ---- Firstboot systemd service ----
cat > "${ROOTFS}/usr/lib/systemd/system/straturaos-firstboot.service" <<'EOF'
[Unit]
Description=StraturaOS First Boot Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/straturaos/.firstboot-done

[Service]
Type=oneshot
ExecStart=/usr/lib/straturaos/firstboot.sh
RemainAfterExit=yes
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Enable firstboot service
install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/straturaos-firstboot.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/straturaos-firstboot.service"

# ---- Strip docs/man/locales/firmware to reduce ISO size ----
echo "Stripping docs/man/locales/firmware..."
rm -rf "${ROOTFS}/usr/share/doc"
rm -rf "${ROOTFS}/usr/share/man"
rm -rf "${ROOTFS}/usr/share/info"
rm -rf "${ROOTFS}/usr/lib/firmware"
find "${ROOTFS}/usr/share/locale" -mindepth 1 -maxdepth 1 \
    ! -name 'C' ! -name 'en_US' -exec rm -rf {} + 2>/dev/null || true

echo "x86_64 customization complete."
