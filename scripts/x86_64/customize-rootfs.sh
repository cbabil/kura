#!/bin/bash
# scripts/x86_64/customize-rootfs.sh
# x86 PC rootfs customizations (target pc). The image runs on real hardware
# such as the Intel NUC, so firmware, kernel modules and time zones stay;
# only documentation and translations are removed.
#
# Usage: customize-rootfs.sh <rootfs-dir>

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/brand-defaults.sh"
BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"

echo "Applying x86_64-specific customization..."

# The QEMU guest agent is not enabled here: its package starts it when a VM
# exposes the agent's virtio port, and on bare metal it would wait for that
# device at every boot.

# ---- Keep the EFI partition's shim and GRUB current ----
# Nothing runs grub-install on this image: after every APT run, sync-efi.sh
# copies newer signed binaries onto the EFI partition (mounted at /boot/efi).
install -d "${ROOTFS}/usr/lib/${BRAND}" "${ROOTFS}/etc/apt/apt.conf.d" "${ROOTFS}/boot/efi"
install -m 0755 "${SCRIPT_DIR}/sync-efi.sh" "${ROOTFS}/usr/lib/${BRAND}/sync-efi.sh"
install -m 0644 "${SCRIPT_DIR}/efi-files.list" "${ROOTFS}/usr/lib/${BRAND}/efi-files.list"
cat > "${ROOTFS}/etc/apt/apt.conf.d/90${BRAND}-efi" <<EOF
DPkg::Post-Invoke { "if [ -x /usr/lib/${BRAND}/sync-efi.sh ]; then /usr/lib/${BRAND}/sync-efi.sh; fi"; };
EOF

# ---- Serial console (VMs and the CI boot test) ----
# The kernel is told of ttyS0 (pc-image.sh), and systemd starts a login
# prompt on every serial console the kernel has. A PC without the port
# still has its name, and its kernel still lists it, so the prompt failed
# and was restarted every ten seconds. It now starts only if the port
# answers; a condition that fails skips the unit without a restart.
# (Kura used to force the prompt with a link: migration 003 removes it.)
install -d "${ROOTFS}/usr/lib/systemd/system/serial-getty@.service.d"
cat > "${ROOTFS}/usr/lib/systemd/system/serial-getty@.service.d/10-${BRAND}.conf" <<'EOF'
[Service]
ExecCondition=/bin/sh -c 'stty -F /dev/%I >/dev/null 2>&1'
EOF

# ---- Strip documentation and translations ----
echo "Stripping docs/man/locales..."
rm -rf "${ROOTFS}/usr/share/doc" "${ROOTFS}/usr/share/man" "${ROOTFS}/usr/share/info"
if [ -d "${ROOTFS}/usr/share/locale" ]; then
    find "${ROOTFS}/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name 'C' ! -name 'en_US' -exec rm -rf {} +
fi
rm -rf "${ROOTFS}/usr/share/i18n/charmaps" "${ROOTFS}/usr/share/i18n/locales"

echo "x86_64 customization complete."
