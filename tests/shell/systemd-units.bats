#!/usr/bin/env bats
# tests/shell/systemd-units.bats — tests for scripts/common/systemd-units.sh

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/systemd-units.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
}

@test "enable_unit: links the unit into the target's wants directory" {
    run enable_unit "${ROOTFS}" multi-user.target /usr/lib/systemd/system/docker.service
    [ "$status" -eq 0 ]
    [ "$(readlink "${ROOTFS}/etc/systemd/system/multi-user.target.wants/docker.service")" = \
      "/usr/lib/systemd/system/docker.service" ]
}

@test "enable_unit: works for other targets and units outside /usr/lib" {
    run enable_unit "${ROOTFS}" sysinit.target /etc/systemd/system/example.service
    [ "$status" -eq 0 ]
    [ "$(readlink "${ROOTFS}/etc/systemd/system/sysinit.target.wants/example.service")" = \
      "/etc/systemd/system/example.service" ]
}

@test "enable_unit: is safe to repeat" {
    enable_unit "${ROOTFS}" multi-user.target /usr/lib/systemd/system/docker.service
    run enable_unit "${ROOTFS}" multi-user.target /usr/lib/systemd/system/docker.service
    [ "$status" -eq 0 ]
}
