#!/bin/bash
# tests/boot/installer-test.sh <installer-image> <pc-image> <out-dir> [ssh-port]
#
# Runs the PC installer (ADR-017) in QEMU as on a NUC: UEFI with Secure Boot
# and Microsoft's keys, the installer image as a USB key holding a
# kura-setup.json (as Etchwise writes it), and a blank 8 GiB virtio disk as
# the internal drive. Instead of GitHub, the installer gets a manifest from
# a local HTTP server (kura.manifest= added to the key's grub.cfg) that
# serves the PC image just built. It must write the internal drive, hand
# over the setup file, mark the key and power off. The internal drive is
# then booted alone by boot-test.sh --installed, which runs the usual checks
# (setup applied, SSH key login, Secure Boot, first boot, root grown...).
# The installer's screen is saved every few seconds (installer-NN.png, at
# 1920x1080 as on a NUC). Images may be .img or .img.zst. Needs what boot-test.sh needs, plus
# python3 for the HTTP server.

set -euo pipefail

USAGE="Usage: $0 <installer-image> <pc-image> <out-dir> [ssh-port]"
INSTALLER="${1:?${USAGE}}"
PC_IMAGE="${2:?${USAGE}}"
OUT="${3:?${USAGE}}"
SSH_PORT="${4:-2224}"
HTTP_PORT=8088
BOOT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "${OUT}/serve" "${OUT}/installed"
OUT="$(cd "${OUT}" && pwd)"
SERIAL="${OUT}/serial.log" REPORT="${OUT}/report.txt"
MONITOR="${OUT}/monitor.sock"
KEY="${OUT}/installed/id_ed25519"
LOGIN_PASS="Kura-$(openssl rand -hex 8)"
: > "${REPORT}"

if [ -w /dev/kvm ]; then ACCEL=(-accel kvm -cpu host); WAIT_SECS=900
else ACCEL=(-accel tcg); WAIT_SECS=2400; fi
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.ms.fd

HTTP_PID="" SCREENS_PID=""
stop_server() {
    # Already stopped after the install, so this kill may fail: never let the
    # EXIT trap turn a passing run into a failure (set -e applies in traps)
    [ -n "${SCREENS_PID}" ] && kill "${SCREENS_PID}" 2>/dev/null || true
    [ -n "${HTTP_PID}" ] && kill "${HTTP_PID}" 2>/dev/null || true
}
trap stop_server EXIT

# shellcheck source=tests/boot/boot-checks.sh
source "${BOOT_DIR}/boot-checks.sh"
# shellcheck source=scripts/pc-installer/installer-image.sh
source "${BOOT_DIR}/../../scripts/pc-installer/installer-image.sh"
# shellcheck source=scripts/common/hash.sh
source "${BOOT_DIR}/../../scripts/common/hash.sh"

# installer_screens: a screenshot every 4 s while the installer runs
# (installer-NN.png, at most 99), run in the background
installer_screens() {
    local n
    for n in $(seq -w 1 99); do
        sleep 4
        [ -S "${MONITOR}" ] && screendump "${OUT}/installer-${n}.png" 2>/dev/null || true
    done
}

# efi_has <disk-image> <file>: <file> is on the image's EFI partition
efi_has() { mdir -i "$1@@$(( PC_EFI_START * 512 ))" "::/$2" >/dev/null 2>&1; }

# ---- the release, served locally ----

SERVED="${OUT}/serve/kura-pc.img.zst"
case "${PC_IMAGE}" in
    *.zst)
        cp "${PC_IMAGE}" "${SERVED}"
        zstd -q -d -f -o "${OUT}/pc.img" "${SERVED}"
        RAW="${OUT}/pc.img" ;;
    *)
        zstd -q -T0 -f "${PC_IMAGE}" -o "${SERVED}"
        RAW="${PC_IMAGE}" ;;
esac
PC_BYTES=$(stat -c %s "${RAW}")
jq -n --arg url "http://10.0.2.2:${HTTP_PORT}/kura-pc.img.zst" \
      --arg sha256 "$(file_sha256 "${SERVED}")" --argjson size "$(stat -c %s "${SERVED}")" \
      --arg extract_sha256 "$(file_sha256 "${RAW}")" --argjson extract_size "${PC_BYTES}" \
      '{version: "test", bundles: {x86_64: {url: $url, sha256: $sha256, size: $size,
        extract_sha256: $extract_sha256, extract_size: $extract_size}}}' > "${OUT}/serve/manifest.json"
rm -f "${OUT}/pc.img"
python3 -m http.server "${HTTP_PORT}" --bind 127.0.0.1 --directory "${OUT}/serve" \
    > "${OUT}/http.log" 2>&1 &
HTTP_PID=$!

# ---- the USB key and the internal drive ----

KEY_IMG="${OUT}/key.img"
EFI="${KEY_IMG}@@$(( PC_EFI_START * 512 ))"
case "${INSTALLER}" in
    *.zst) zstd -q -d -f -o "${KEY_IMG}" "${INSTALLER}" ;;
    *) cp "${INSTALLER}" "${KEY_IMG}" ;;
esac
make_setup_file "${OUT}/kura-setup.json"
mcopy -o -i "${EFI}" "${OUT}/kura-setup.json" ::/kura-setup.json
installer_grub_cfg "${INSTALLER_LABEL}" Kura \
    "kura.manifest=http://10.0.2.2:${HTTP_PORT}/manifest.json" > "${OUT}/grub.cfg"
mcopy -o -i "${EFI}" "${OUT}/grub.cfg" "::/${PC_GRUB_CFG}"
INTERNAL="${OUT}/internal.img"
rm -f "${INTERNAL}"
truncate -s 8G "${INTERNAL}"

# ---- install ----

cp "${OVMF_VARS}" "${OUT}/ovmf-vars.fd"
rm -f "${OUT}"/installer-*.png "${MONITOR}"
installer_screens &
SCREENS_PID=$!
report "Installing from ${INSTALLER} (UEFI Secure Boot, ${ACCEL[*]}, wait ${WAIT_SECS}s)"
install_status=0
timeout "${WAIT_SECS}" qemu-system-x86_64 -machine q35,smm=on -m 2048 -smp 2 "${ACCEL[@]}" \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${OUT}/ovmf-vars.fd" \
    -device qemu-xhci \
    -drive "if=none,id=key,format=raw,file=${KEY_IMG}" -device usb-storage,drive=key,bootindex=0 \
    -drive "if=none,id=internal,format=raw,file=${INTERNAL}" \
    -device virtio-blk-pci,drive=internal,bootindex=1 \
    -nic user,model=virtio-net-pci \
    -vga none -device VGA,xres=1920,yres=1080 \
    -display none -monitor "unix:${MONITOR},server,nowait" -serial "file:${SERIAL}" \
    -no-reboot || install_status=$?
kill "${SCREENS_PID}" 2>/dev/null || true
report "Installer screenshots: $(find "${OUT}" -maxdepth 1 -name 'installer-*.png' | wc -l)"

key_lacks() { ! efi_has "${KEY_IMG}" "$1"; }

check "installer powered off by itself" test "${install_status}" -eq 0
check "installer says Kura is installed" grep -q "Kura is installed on" "${SERIAL}"
check "image downloaded from the manifest" grep -q "kura-pc.img.zst" "${OUT}/http.log"
check "setup file handed to the installed system" efi_has "${INTERNAL}" kura-setup.json
check "setup file removed from the key" key_lacks kura-setup.json
check "key marked as used" efi_has "${KEY_IMG}" .installed
if [ "${FAILED}" -ne 0 ]; then
    report "RESULT: FAILED"
    exit 1
fi

# ---- boot the internal drive alone ----

KURA_TEST_LOGIN_PASS="${LOGIN_PASS}" KURA_TEST_IMAGE_BYTES="${PC_BYTES}" \
    "${BOOT_DIR}/boot-test.sh" "${INTERNAL}" "${OUT}/installed" "${SSH_PORT}" --installed
report "RESULT: PASSED"
