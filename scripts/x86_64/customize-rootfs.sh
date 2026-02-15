#!/bin/bash
# scripts/x86_64/customize-rootfs.sh
# x86_64-specific rootfs customization.
# Adapted from buildroot-external post-build.sh
#
# Usage: customize-rootfs.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/../common/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"

echo "Applying x86_64-specific customization..."

# ---- QEMU guest agent (Proxmox/KVM integration) ----
install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/qemu-guest-agent.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"

# ---- Serial console ----
install -d "${ROOTFS}/etc/systemd/system/getty.target.wants"
ln -sf /usr/lib/systemd/system/serial-getty@.service \
    "${ROOTFS}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# ---- Firstboot service ----
install -d "${ROOTFS}/usr/lib/${BRAND}os"
cat > "${ROOTFS}/usr/lib/${BRAND}os/firstboot.sh" <<'FBEOF'
#!/bin/bash
# __BRAND_NAME__ first-boot script (x86_64 ISO target)
# Resizes root partition, installs Docker, generates SSH keys, cloud-init.

FIRSTBOOT_FLAG="/var/lib/__BRAND__os/.firstboot-done"
LOGFILE="/var/log/__BRAND__/firstboot.log"

[ -f "${FIRSTBOOT_FLAG}" ] && exit 0

mkdir -p "$(dirname "${LOGFILE}")"
exec > >(tee -a "${LOGFILE}") 2>&1

echo "$(date): __BRAND_NAME__ first-boot starting..."

export DEBIAN_FRONTEND=noninteractive

# ---- Resize root partition ----
resize_root() {
    local root_dev root_disk root_part
    root_dev=$(findmnt -no SOURCE / 2>/dev/null) || return 0
    root_disk=$(lsblk -ndo PKNAME "${root_dev}" 2>/dev/null) || return 0
    [ -z "${root_disk}" ] && return 0
    root_part=$(echo "${root_dev}" | grep -oP '\d+$') || return 0
    [ -z "${root_part}" ] && return 0
    growpart "/dev/${root_disk}" "${root_part}" 2>&1 || true
    resize2fs "${root_dev}" 2>&1 || true
    echo "Root partition resize attempted."
}
resize_root

# ---- Install Docker (retries up to 6 minutes for network) ----
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        echo "Docker already installed, skipping."
        return 0
    fi

    echo "__BRAND_NAME__: Installing Docker..."

    local arch codename
    arch=$(dpkg --print-architecture)
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    if [ -z "${codename}" ]; then
        echo "ERROR: Cannot determine Debian codename from /etc/os-release"
        return 1
    fi

    install -m 0755 -d /etc/apt/keyrings

    local attempt
    for attempt in $(seq 1 12); do
        echo "Docker install attempt ${attempt}/12..."

        # Step 1: Download GPG key (skip if already done)
        if [ ! -f /etc/apt/keyrings/docker.asc ]; then
            if ! curl -fsSL --connect-timeout 10 --max-time 30 \
                https://download.docker.com/linux/debian/gpg \
                -o /etc/apt/keyrings/docker.asc 2>&1; then
                echo "  GPG key download failed, retrying in 30s..."
                rm -f /etc/apt/keyrings/docker.asc
                sleep 30
                continue
            fi
            chmod a+r /etc/apt/keyrings/docker.asc
        fi

        # Step 2: Create Docker apt source
        echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian ${codename} stable" \
            > /etc/apt/sources.list.d/docker.list

        # Step 3: Update and install
        if apt-get update -qq 2>&1 && \
           apt-get install -y -qq docker-ce docker-ce-cli containerd.io 2>&1; then
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            getent group docker >/dev/null || groupadd -r docker
            systemctl enable docker.service containerd.service
            systemctl start docker.service
            echo "__BRAND_NAME__: Docker installed successfully."
            return 0
        fi

        echo "  apt-get failed, retrying in 30s..."
        sleep 30
    done

    echo "ERROR: Docker installation failed after 12 attempts."
    return 1
}

if ! install_docker; then
    echo "WARNING: Docker installation failed. Check ${LOGFILE} for details."
fi

# ---- Generate SSH host keys ----
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
    echo "SSH host keys generated."
fi

# ---- Cloud-init user-data (if available) ----
for dev in /dev/sr0 /dev/vdb; do
    if [ -b "${dev}" ]; then
        MOUNT_DIR=$(mktemp -d)
        if mount -o ro "${dev}" "${MOUNT_DIR}" 2>/dev/null; then
            if [ -f "${MOUNT_DIR}/user-data" ]; then
                NEW_HOSTNAME=$(grep -oP '^hostname:\s*\K\S+' "${MOUNT_DIR}/user-data" || true)
                if [ -n "${NEW_HOSTNAME}" ]; then
                    hostnamectl set-hostname "${NEW_HOSTNAME}"
                    echo "Hostname set to ${NEW_HOSTNAME}."
                fi
            fi
            umount "${MOUNT_DIR}"
        fi
        rmdir "${MOUNT_DIR}" 2>/dev/null || true
    fi
done

# ---- Mark firstboot complete ----
mkdir -p "$(dirname "${FIRSTBOOT_FLAG}")"
touch "${FIRSTBOOT_FLAG}"
echo "$(date): __BRAND_NAME__ first-boot complete."
FBEOF

# Replace placeholders in firstboot script with actual brand values
sed -i "s|__BRAND_NAME__|${OS_NAME}|g; s|__BRAND__|${BRAND}|g" \
    "${ROOTFS}/usr/lib/${BRAND}os/firstboot.sh"
chmod 755 "${ROOTFS}/usr/lib/${BRAND}os/firstboot.sh"

# ---- Firstboot systemd service ----
cat > "${ROOTFS}/usr/lib/systemd/system/${BRAND}os-firstboot.service" <<SVCEOF
[Unit]
Description=${OS_NAME} First Boot Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/${BRAND}os/.firstboot-done

[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/usr/lib/${BRAND}os/firstboot.sh
RemainAfterExit=yes
TimeoutStartSec=600
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
SVCEOF

# Enable firstboot service
install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sf "/usr/lib/systemd/system/${BRAND}os-firstboot.service" \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${BRAND}os-firstboot.service"

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
