#!/bin/bash
# StraturaOS x86_64 post-build script

set -e

BOARD_DIR="$(dirname $0)"
TARGET_DIR=$1

echo "StraturaOS x86_64: Running post-build..."

# Create required directories for stratura services
mkdir -p "${TARGET_DIR}/var/lib/stratura"
mkdir -p "${TARGET_DIR}/var/lib/stratura/volumes"
mkdir -p "${TARGET_DIR}/etc/stratura"

# Enable systemd services
if [ -d "${TARGET_DIR}/usr/lib/systemd/system" ]; then
    mkdir -p "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants"

    # Enable NetworkManager
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/NetworkManager.service" ]; then
        ln -sf /usr/lib/systemd/system/NetworkManager.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
        echo "StraturaOS x86_64: Enabled NetworkManager"
    fi

    # Enable Docker
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/docker.service" ]; then
        ln -sf /usr/lib/systemd/system/docker.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/docker.service"
        echo "StraturaOS x86_64: Enabled Docker"
    fi

    # Enable containerd
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/containerd.service" ]; then
        ln -sf /usr/lib/systemd/system/containerd.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/containerd.service"
        echo "StraturaOS x86_64: Enabled containerd"
    fi

    # Enable stratura-supervisor
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/stratura-supervisor.service" ]; then
        ln -sf /usr/lib/systemd/system/stratura-supervisor.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/stratura-supervisor.service"
        echo "StraturaOS x86_64: Enabled stratura-supervisor"
    fi

    # Enable SSH
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/sshd.service" ]; then
        ln -sf /usr/lib/systemd/system/sshd.service \
            "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/sshd.service"
        echo "StraturaOS x86_64: Enabled SSH"
    fi

    # Create a simple first-boot service for cloud-init style config
    cat > "${TARGET_DIR}/usr/lib/systemd/system/straturaos-firstboot.service" << 'SVCEOF'
[Unit]
Description=StraturaOS First Boot Configuration
ConditionPathExists=!/etc/straturaos-firstboot-done
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/straturaos-firstboot
ExecStartPost=/usr/bin/touch /etc/straturaos-firstboot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

    ln -sf /usr/lib/systemd/system/straturaos-firstboot.service \
        "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/straturaos-firstboot.service"
fi

# Create first-boot script
mkdir -p "${TARGET_DIR}/usr/sbin"
cat > "${TARGET_DIR}/usr/sbin/straturaos-firstboot" << 'FBEOF'
#!/bin/bash
# StraturaOS First Boot Script

echo "StraturaOS: Running first boot configuration..."

# Resize root partition to fill disk
# Try growpart first, fall back to fdisk/resize2fs
resize_root() {
    ROOT_DEV=$(findmnt -n -o SOURCE /)
    ROOT_DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
    ROOT_PART=$(echo "$ROOT_DEV" | grep -o '[0-9]*$')

    if command -v growpart &> /dev/null; then
        growpart "$ROOT_DISK" "$ROOT_PART" 2>/dev/null || true
    fi

    # Always try resize2fs
    if command -v resize2fs &> /dev/null; then
        resize2fs "$ROOT_DEV" 2>/dev/null || true
    fi
}

resize_root

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "StraturaOS: Generating SSH host keys..."
    ssh-keygen -A 2>/dev/null || true
fi

# Check for cloud-init datasource (NoCloud via CD-ROM)
if [ -b /dev/sr0 ]; then
    mkdir -p /mnt/cidata
    mount /dev/sr0 /mnt/cidata 2>/dev/null || true

    if [ -f /mnt/cidata/user-data ]; then
        echo "StraturaOS: Found cloud-init data"
        # Parse basic user-data (simplified)
        if grep -q "hostname:" /mnt/cidata/user-data; then
            NEW_HOSTNAME=$(grep "hostname:" /mnt/cidata/user-data | awk '{print $2}')
            if [ -n "$NEW_HOSTNAME" ]; then
                hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || \
                    echo "$NEW_HOSTNAME" > /etc/hostname
            fi
        fi
    fi

    if [ -f /mnt/cidata/meta-data ]; then
        echo "StraturaOS: Found meta-data"
    fi

    umount /mnt/cidata 2>/dev/null || true
fi

# Check for NoCloud datasource via /dev/vdb (common in Proxmox)
if [ -b /dev/vdb ]; then
    mkdir -p /mnt/cidata
    mount /dev/vdb /mnt/cidata 2>/dev/null || true

    if [ -f /mnt/cidata/user-data ]; then
        echo "StraturaOS: Found cloud-init data on vdb"
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

echo "StraturaOS: First boot complete"
FBEOF
chmod +x "${TARGET_DIR}/usr/sbin/straturaos-firstboot"

# Set up serial console for cloud
mkdir -p "${TARGET_DIR}/etc/systemd/system/serial-getty@ttyS0.service.d"
cat > "${TARGET_DIR}/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,57600,38400,9600 %I $TERM
EOF

# Create default supervisor config if not exists
if [ ! -f "${TARGET_DIR}/etc/stratura/supervisor-config.json" ]; then
    cat > "${TARGET_DIR}/etc/stratura/supervisor-config.json" << 'EOF'
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

echo "StraturaOS x86_64: Post-build complete"
