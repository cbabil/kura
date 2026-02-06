#!/bin/bash
# StraturaOS VM Disk Partitioning Script
# WARNING: This will DESTROY ALL DATA on the target disk
# Run from a Debian/Ubuntu Live ISO
#
# Recommended disk size: 110GB+
#
# Partition layout:
#   /dev/sda1 - 512MB  - /boot/efi (EFI)
#   /dev/sda2 - 15GB   - / (root)
#   /dev/sda3 - 10GB   - /var (docker, logs)
#   /dev/sda4 - 10GB   - /tmp (build temp files)
#   /dev/sda5 - 8GB    - swap
#   /dev/sda6 - rest   - /home (buildroot, source, releases)

set -e

DISK="${1:-/dev/sda}"

echo "============================================"
echo "StraturaOS VM Disk Partitioning"
echo "============================================"
echo ""
echo "Target disk: ${DISK}"
echo ""
echo "This will create:"
echo "  ${DISK}1 - 512MB  - /boot/efi"
echo "  ${DISK}2 - 15GB   - /"
echo "  ${DISK}3 - 10GB   - /var"
echo "  ${DISK}4 - 10GB   - /tmp"
echo "  ${DISK}5 - 8GB    - swap"
echo "  ${DISK}6 - rest   - /home"
echo ""
echo "WARNING: This will ERASE ALL DATA on ${DISK}"
echo ""
read -p "Type YES to continue: " confirm
if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Check if disk exists
if [ ! -b "${DISK}" ]; then
    echo "ERROR: ${DISK} not found"
    exit 1
fi

# Check disk size (should be at least 50GB)
DISK_SIZE=$(lsblk -b -d -n -o SIZE ${DISK})
MIN_SIZE=$((50 * 1024 * 1024 * 1024))
if [ "${DISK_SIZE}" -lt "${MIN_SIZE}" ]; then
    echo "ERROR: Disk too small. Need at least 50GB, have $(( DISK_SIZE / 1024 / 1024 / 1024 ))GB"
    exit 1
fi

echo ""
echo "Unmounting existing partitions..."
umount ${DISK}* 2>/dev/null || true
swapoff ${DISK}* 2>/dev/null || true

echo "Creating GPT partition table..."
parted -s ${DISK} mklabel gpt

echo "Creating partitions..."
parted -s ${DISK} mkpart primary fat32 1MiB 513MiB         # EFI
parted -s ${DISK} set 1 esp on
parted -s ${DISK} mkpart primary ext4 513MiB 15.5GiB       # /
parted -s ${DISK} mkpart primary ext4 15.5GiB 25.5GiB      # /var
parted -s ${DISK} mkpart primary ext4 25.5GiB 35.5GiB      # /tmp
parted -s ${DISK} mkpart primary linux-swap 35.5GiB 43.5GiB # swap
parted -s ${DISK} mkpart primary ext4 43.5GiB 100%         # /home

echo "Formatting partitions..."
mkfs.fat -F32 ${DISK}1
mkfs.ext4 -F ${DISK}2
mkfs.ext4 -F ${DISK}3
mkfs.ext4 -F ${DISK}4
mkswap ${DISK}5
mkfs.ext4 -F ${DISK}6

echo ""
echo "============================================"
echo "Partitioning complete!"
echo "============================================"
echo ""
lsblk ${DISK}
echo ""
echo "Next steps:"
echo "1. Run the Debian/Ubuntu installer"
echo "2. Choose 'Manual' partitioning"
echo "3. Assign mount points:"
echo "   ${DISK}1 -> /boot/efi (EFI System Partition)"
echo "   ${DISK}2 -> /"
echo "   ${DISK}3 -> /var"
echo "   ${DISK}4 -> /tmp"
echo "   ${DISK}5 -> swap"
echo "   ${DISK}6 -> /home"
echo "4. Complete installation"
echo "5. After reboot, run:"
echo "   mkdir -p /home/straturaos"
echo "   cd /home/straturaos"
echo "   git clone <repo-url> ."
echo "   ./build.sh setup"
echo "   ./build.sh install"
echo "   straturaos build"
echo ""
