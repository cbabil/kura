#!/bin/bash
# scripts/x86_64/sync-efi.sh
# Runs on the PC after every APT run (/etc/apt/apt.conf.d/90<brand>-efi):
# copies a newer signed GRUB or shim from their packages onto the EFI
# partition, which nothing else updates (the image has no grub-install), so
# security fixes and revocation-proof versions reach the boot path. Installed
# with efi-files.list next to it by scripts/x86_64/customize-rootfs.sh.

set -euo pipefail

ROOT="${SYNC_ROOT:-}"   # tests point this at a scratch root
EFI="${ROOT}/boot/efi"
LIST="${SYNC_EFI_LIST:-$(dirname "$0")/efi-files.list}"

mountpoint -q "${EFI}" || exit 0

while read -r src dest; do
    [ -f "${ROOT}/${src}" ] || continue
    cmp -s "${ROOT}/${src}" "${EFI}/${dest}" && continue
    mkdir -p "$(dirname "${EFI}/${dest}")"
    cp "${ROOT}/${src}" "${EFI}/${dest}.new"
    mv "${EFI}/${dest}.new" "${EFI}/${dest}"
    echo "Updated ${dest} on the EFI partition"
done < <(grep -v '^#' "${LIST}")
sync
