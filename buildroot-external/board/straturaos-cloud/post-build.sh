#!/bin/bash
# StraturaOS Cloud post-build script

set -e

BOARD_DIR="$(dirname $0)"
TARGET_DIR=$1

echo "StraturaOS Cloud: Running post-build..."

# Create EFI directory structure
mkdir -p "${BINARIES_DIR}/EFI/BOOT"

# Copy GRUB EFI binary
if [ -f "${BINARIES_DIR}/grub-efi-bootx64.efi" ]; then
    cp "${BINARIES_DIR}/grub-efi-bootx64.efi" "${BINARIES_DIR}/EFI/BOOT/bootx64.efi"
fi

# Create GRUB config
cat > "${BINARIES_DIR}/EFI/BOOT/grub.cfg" << 'EOF'
set timeout=3
set default=0

menuentry "StraturaOS" {
    linux /boot/bzImage root=/dev/vda2 rw console=tty0 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0
}
EOF

# Enable cloud-init services if available
if [ -d "${TARGET_DIR}/usr/lib/systemd/system" ]; then
    mkdir -p "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants"

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
if command -v growpart &> /dev/null; then
    growpart /dev/vda 2 || true
    resize2fs /dev/vda2 || true
fi

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# Check for cloud-init datasource (NoCloud, etc.)
if [ -b /dev/sr0 ]; then
    mkdir -p /mnt/cidata
    mount /dev/sr0 /mnt/cidata 2>/dev/null || true

    if [ -f /mnt/cidata/user-data ]; then
        echo "StraturaOS: Found cloud-init data"
        # Parse basic user-data (simplified)
        if grep -q "hostname:" /mnt/cidata/user-data; then
            NEW_HOSTNAME=$(grep "hostname:" /mnt/cidata/user-data | awk '{print $2}')
            hostnamectl set-hostname "$NEW_HOSTNAME"
        fi
    fi

    if [ -f /mnt/cidata/meta-data ]; then
        echo "StraturaOS: Found meta-data"
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

echo "StraturaOS Cloud: Post-build complete"
