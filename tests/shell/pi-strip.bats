#!/usr/bin/env bats
# tests/shell/pi-strip.bats — shrinking the Pi image must not remove what the
# device needs: its Wi-Fi firmware and the time zones first boot can set
# (scripts/rpi5/strip-rootfs.sh).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/rpi5/strip-rootfs.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    FW="${ROOTFS}/usr/lib/firmware"
    mkdir -p "${FW}/brcm" "${FW}/cypress" "${FW}/intel" "${FW}/amdgpu"
    touch "${FW}/brcm/brcmfmac43455-sdio.bin" "${FW}/cypress/cyfmac43455-sdio.bin" \
          "${FW}/intel/x.bin" "${FW}/amdgpu/y.bin" "${FW}/regulatory.db"
}

@test "strip_firmware: keeps the Pi's Wi-Fi firmware, removes the rest" {
    run strip_firmware "${ROOTFS}"
    [ "$status" -eq 0 ]
    [ -f "${FW}/brcm/brcmfmac43455-sdio.bin" ]
    [ -f "${FW}/cypress/cyfmac43455-sdio.bin" ]
    [ ! -e "${FW}/intel" ]
    [ ! -e "${FW}/amdgpu" ]
}

@test "strip_firmware: keeps the Wi-Fi regulatory database" {
    run strip_firmware "${ROOTFS}"
    [ "$status" -eq 0 ]
    [ -f "${FW}/regulatory.db" ]
}

@test "strip_firmware: stops the build when there is no Wi-Fi firmware" {
    rm -rf "${FW}/brcm"
    run strip_firmware "${ROOTFS}"
    [ "$status" -ne 0 ]
    [[ "${output}" == *"Wi-Fi firmware"* ]]
}

@test "the Pi build strips firmware through strip_firmware and keeps every time zone" {
    local script="${REPO_ROOT}/scripts/rpi5/customize-rootfs.sh"
    grep -q 'strip_firmware "${ROOTFS}"' "${script}"
    ! grep -q 'usr/lib/firmware"$' "${script}"
    ! grep -q 'zoneinfo' "${script}"
}
