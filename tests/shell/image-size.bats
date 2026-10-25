#!/usr/bin/env bats
# tests/shell/image-size.bats — tests for scripts/common/image-size.sh

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
MiB=$((1024 * 1024))

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/image-size.sh"
}

@test "check_rootfs_fits: passes with room to spare" {
    run check_rootfs_fits $((1500 * MiB)) $((2048 * MiB))
    [ "$status" -eq 0 ]
}

@test "check_rootfs_fits: fails when the contents exceed the partition" {
    run check_rootfs_fits $((2200 * MiB)) $((2048 * MiB))
    [ "$status" -eq 1 ]
    output_has "2200 MiB"
    output_has "OS_ROOTFS_SIZE"
}

@test "check_rootfs_fits: keeps 10% headroom for filesystem overhead" {
    run check_rootfs_fits $((1900 * MiB)) $((2048 * MiB))
    [ "$status" -eq 1 ]
}

@test "check_rootfs_fits: suggests a size that fits, rounded up to whole GiB" {
    run check_rootfs_fits $((2200 * MiB)) $((2048 * MiB))
    output_has "OS_ROOTFS_SIZE=3G"
}

@test "check_rootfs_fits: names the setting of the image being built" {
    run check_rootfs_fits $((3500 * MiB)) $((3072 * MiB)) OS_PC_ROOTFS_SIZE
    [ "$status" -eq 1 ]
    output_has "OS_PC_ROOTFS_SIZE=4G"
}

@test "build.sh passes the PC root size on to the image script" {
    grep -q '^OS_PC_ROOTFS_SIZE="${OS_PC_ROOTFS_SIZE:-3G}"' "${REPO_ROOT}/build.sh"
    grep -qE '^export .*OS_PC_ROOTFS_SIZE' "${REPO_ROOT}/build.sh"
}
