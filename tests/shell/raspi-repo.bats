#!/usr/bin/env bats
# tests/shell/raspi-repo.bats — tests for scripts/rpi5/raspi-repo.sh: the
# Raspberry Pi APT repository is verified with the pinned archive key, over
# HTTPS, never trusted blindly.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/rpi5/raspi-repo.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}/etc"
    printf 'ID=debian\nVERSION_CODENAME=trixie\n' > "${ROOTFS}/etc/os-release"
}

@test "the vendored Raspberry Pi key is the pinned one" {
    run pinned_key "${RASPI_KEY_FILE}" "${RASPI_GPG_FINGERPRINT}" "${BATS_TEST_TMPDIR}/out.asc"
    [ "$status" -eq 0 ]
}

@test "install_raspi_repo: HTTPS source checked with the pinned key" {
    run install_raspi_repo "${ROOTFS}"
    [ "$status" -eq 0 ]
    [ "$(cat "${ROOTFS}/etc/apt/sources.list.d/raspi.list")" = \
      "deb [signed-by=/etc/apt/keyrings/raspberrypi-archive.asc] https://archive.raspberrypi.com/debian/ trixie main" ]
    [ -s "${ROOTFS}/etc/apt/keyrings/raspberrypi-archive.asc" ]
    [ "$(file_mode "${ROOTFS}/etc/apt/keyrings/raspberrypi-archive.asc")" = "644" ]
}

@test "install_raspi_repo: refuses a key that does not match the pin" {
    RASPI_GPG_FINGERPRINT="0000000000000000000000000000000000000000"
    run install_raspi_repo "${ROOTFS}"
    [ "$status" -ne 0 ]
    [ ! -e "${ROOTFS}/etc/apt/sources.list.d/raspi.list" ]
}

@test "configure-repos.sh: no trusted=yes and no plain http left" {
    ! grep -n "trusted=yes\|http://" "${REPO_ROOT}/scripts/rpi5/configure-repos.sh"
}
