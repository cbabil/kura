#!/bin/bash
# x86_64 post-build script

set -e

BOARD_DIR="$(dirname $0)"
TARGET_DIR=$1

# Single source of truth for default brand values
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/common/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
API_ENDPOINT="${OS_API_ENDPOINT:-${DEFAULT_API_ENDPOINT}}"
REGISTRY="${OS_REGISTRY:-${DEFAULT_REGISTRY}}"
API_DOMAIN="${API_ENDPOINT#*://}"
BASE_DOMAIN="${API_DOMAIN#*.}"
UPDATES_DOMAIN="updates.${BASE_DOMAIN}"

echo "${OS_NAME} x86_64: Running post-build..."

# Create required directories for branded services
mkdir -p "${TARGET_DIR}/var/lib/${BRAND}"
mkdir -p "${TARGET_DIR}/var/lib/${BRAND}/volumes"
mkdir -p "${TARGET_DIR}/etc/${BRAND}"

# Enable systemd services
if [ -d "${TARGET_DIR}/usr/lib/systemd/system" ]; then
    mkdir -p "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants"

    # Enable NetworkManager
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/NetworkManager.service" ]; then
        ln -sf /usr/lib/systemd/system/NetworkManager.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
        echo "${OS_NAME} x86_64: Enabled NetworkManager"
    fi

    # Enable Docker
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/docker.service" ]; then
        ln -sf /usr/lib/systemd/system/docker.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/docker.service"
        echo "${OS_NAME} x86_64: Enabled Docker"
    fi

    # Enable containerd
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/containerd.service" ]; then
        ln -sf /usr/lib/systemd/system/containerd.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/containerd.service"
        echo "${OS_NAME} x86_64: Enabled containerd"
    fi

    # Enable ${BRAND}-supervisor
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/${BRAND}-supervisor.service" ]; then
        ln -sf /usr/lib/systemd/system/${BRAND}-supervisor.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/${BRAND}-supervisor.service"
        echo "${OS_NAME} x86_64: Enabled ${BRAND}-supervisor"
    fi

    # Enable SSH
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/sshd.service" ]; then
        ln -sf /usr/lib/systemd/system/sshd.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/sshd.service"
        echo "${OS_NAME} x86_64: Enabled SSH"
    fi

    # Create a simple first-boot service for cloud-init style config
    cat > "${TARGET_DIR}/usr/lib/systemd/system/${BRAND}os-firstboot.service" << SVCEOF
[Unit]
Description=${OS_NAME} First Boot Configuration
ConditionPathExists=!/etc/${BRAND}os-firstboot-done
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/${BRAND}os-firstboot
ExecStartPost=/usr/bin/touch /etc/${BRAND}os-firstboot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

    ln -sf "/usr/lib/systemd/system/${BRAND}os-firstboot.service" \
        "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/${BRAND}os-firstboot.service"
fi

# Create first-boot script
mkdir -p "${TARGET_DIR}/usr/sbin"
cat > "${TARGET_DIR}/usr/sbin/${BRAND}os-firstboot" << 'FBEOF'
#!/bin/bash
# __BRAND_NAME__ First Boot Script

echo "__BRAND_NAME__: Running first boot configuration..."

# Resize root partition to fill disk
resize_root() {
    ROOT_DEV=$(findmnt -n -o SOURCE /)
    ROOT_DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
    ROOT_PART=$(echo "$ROOT_DEV" | grep -o '[0-9]*$')

    if command -v growpart &> /dev/null; then
        growpart "$ROOT_DISK" "$ROOT_PART" 2>/dev/null || true
    fi

    if command -v resize2fs &> /dev/null; then
        resize2fs "$ROOT_DEV" 2>/dev/null || true
    fi
}

resize_root

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "__BRAND_NAME__: Generating SSH host keys..."
    ssh-keygen -A 2>/dev/null || true
fi

# Check for cloud-init datasource (NoCloud via CD-ROM)
if [ -b /dev/sr0 ]; then
    mkdir -p /mnt/cidata
    mount /dev/sr0 /mnt/cidata 2>/dev/null || true

    if [ -f /mnt/cidata/user-data ]; then
        echo "__BRAND_NAME__: Found cloud-init data"
        if grep -q "hostname:" /mnt/cidata/user-data; then
            NEW_HOSTNAME=$(grep "hostname:" /mnt/cidata/user-data | awk '{print $2}')
            if [ -n "$NEW_HOSTNAME" ]; then
                hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || \
                    echo "$NEW_HOSTNAME" > /etc/hostname
            fi
        fi
    fi

    if [ -f /mnt/cidata/meta-data ]; then
        echo "__BRAND_NAME__: Found meta-data"
    fi

    umount /mnt/cidata 2>/dev/null || true
fi

# Check for NoCloud datasource via /dev/vdb (common in Proxmox)
if [ -b /dev/vdb ]; then
    mkdir -p /mnt/cidata
    mount /dev/vdb /mnt/cidata 2>/dev/null || true

    if [ -f /mnt/cidata/user-data ]; then
        echo "__BRAND_NAME__: Found cloud-init data on vdb"
        if grep -q "hostname:" /mnt/cidata/user-data; then
            NEW_HOSTNAME=$(grep "hostname:" /mnt/cidata/user-data | awk '{print $2}')
            if [ -n "$NEW_HOSTNAME" ]; then
                hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || \
                    echo "$NEW_HOSTNAME" > /etc/hostname
            fi
        fi
    fi

    umount /mnt/cidata 2>/dev/null || true
fi

echo "__BRAND_NAME__: First boot complete"
FBEOF

# Replace placeholders in firstboot script with actual brand values
sed -i "s|__BRAND_NAME__|${OS_NAME}|g; s|__BRAND__|${BRAND}|g" \
    "${TARGET_DIR}/usr/sbin/${BRAND}os-firstboot"
chmod +x "${TARGET_DIR}/usr/sbin/${BRAND}os-firstboot"

# Set up serial console for cloud
mkdir -p "${TARGET_DIR}/etc/systemd/system/serial-getty@ttyS0.service.d"
cat > "${TARGET_DIR}/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,57600,38400,9600 %I $TERM
EOF

# Create default supervisor config if not exists
if [ ! -f "${TARGET_DIR}/etc/${BRAND}/supervisor-config.json" ]; then
    cat > "${TARGET_DIR}/etc/${BRAND}/supervisor-config.json" << 'EOF'
{
    "applications": [],
    "poll_interval": 60,
    "api_endpoint": ""
}
EOF
fi

# Create docker group
if ! grep -q "^docker:" "${TARGET_DIR}/etc/group" 2>/dev/null; then
    echo "docker:x:998:" >> "${TARGET_DIR}/etc/group"
fi

# Patch Python sources: replace __BRAND__ placeholder with actual brand
for pyfile in "${TARGET_DIR}/usr/lib/${BRAND}/security_hardening.py" \
              "${TARGET_DIR}/usr/lib/${BRAND}/network_manager.py"; do
    if [ -f "${pyfile}" ]; then
        sed -i "s|__BRAND__|${BRAND}|g" "${pyfile}"
    fi
done

# Patch hardening.json: replace domain placeholders with actual values
if [ -f "${TARGET_DIR}/etc/${BRAND}/security/hardening.json" ]; then
    sed -i "s|__REGISTRY__|${REGISTRY}|g; \
            s|__API_DOMAIN__|${API_DOMAIN}|g; \
            s|__UPDATES_DOMAIN__|${UPDATES_DOMAIN}|g" \
        "${TARGET_DIR}/etc/${BRAND}/security/hardening.json"
fi

# Patch service file placeholders
for svc_file in "${BRAND}-supervisor" "${BRAND}-config" "${BRAND}-security"; do
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/${svc_file}.service" ]; then
        sed -i "s|__BRAND__|${BRAND}|g; s|__BRAND_NAME__|${OS_NAME}|g; s|__BRAND_API__|${API_DOMAIN}|g" \
            "${TARGET_DIR}/usr/lib/systemd/system/${svc_file}.service"
    fi
done

# Patch NetworkManager config placeholder
if [ -f "${TARGET_DIR}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf" ]; then
    sed -i "s|__BRAND_API__|${API_DOMAIN}|g" \
        "${TARGET_DIR}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf"
fi

echo "${OS_NAME} x86_64: Post-build complete"
