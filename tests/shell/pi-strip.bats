#!/usr/bin/env bats
# tests/shell/pi-strip.bats — shrinking the Pi image must not remove what the
# device needs: its Wi-Fi firmware and the time zones first boot can set
# (scripts/rpi5/strip-rootfs.sh).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
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

@test "require_dm_mod: passes with device-mapper as a module or built in" {
    local mods="${ROOTFS}/lib/modules/6.12.47+rpt-rpi-2712"
    mkdir -p "${mods}/kernel/drivers/md"
    touch "${mods}/kernel/drivers/md/dm-mod.ko.xz"
    run require_dm_mod "${ROOTFS}"
    [ "$status" -eq 0 ]
    rm "${mods}/kernel/drivers/md/dm-mod.ko.xz"
    echo "kernel/drivers/md/dm-mod.ko" > "${mods}/modules.builtin"
    run require_dm_mod "${ROOTFS}"
    [ "$status" -eq 0 ]
}

@test "require_dm_mod: checks the Pi 5 kernel (2712), not another one" {
    mkdir -p "${ROOTFS}/lib/modules/6.12.47+rpt-rpi-v8/kernel/drivers/md" "${ROOTFS}/lib/modules/6.12.47+rpt-rpi-2712/kernel"
    touch "${ROOTFS}/lib/modules/6.12.47+rpt-rpi-v8/kernel/drivers/md/dm-mod.ko.xz"
    run require_dm_mod "${ROOTFS}"
    [ "$status" -ne 0 ]
}

@test "require_dm_mod: fails without device-mapper (no disk layout volumes)" {
    mkdir -p "${ROOTFS}/lib/modules/6.12.47+rpt-rpi-2712/kernel"
    run require_dm_mod "${ROOTFS}"
    [ "$status" -ne 0 ]
    output_has "dm-mod"
}

@test "the Pi build checks for device-mapper" {
    file_has "${REPO_ROOT}/scripts/rpi5/customize-rootfs.sh" 'require_dm_mod "${ROOTFS}"'
}
