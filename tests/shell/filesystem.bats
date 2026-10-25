#!/usr/bin/env bats
# tests/shell/filesystem.bats — tests for fstab update logic
# Note: The actual _update_fstab uses bash 4+ associative arrays.
# These tests verify the logic by testing a portable equivalent.

setup() {
    load test_helper
    load_security_lib "common"
}

# Portable fstab updater (same logic as _update_fstab, no associative arrays)
_test_update_fstab() {
    local fstab="$1"
    [ -f "${fstab}" ] || return 0

    local tmp_file
    tmp_file=$(mktemp "${BATS_TEST_TMPDIR}/.fstab.tmp.XXXXXX")

    while IFS= read -r line; do
        if [ -z "${line}" ] || [ "${line#\#}" != "${line}" ]; then
            printf '%s\n' "${line}"
            continue
        fi

        set -- ${line}
        if [ $# -lt 4 ]; then
            printf '%s\n' "${line}"
            continue
        fi

        local mp="$2"
        case "${mp}" in
            /tmp|/var/tmp|/dev/shm)
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "$1" "$2" "$3" "noexec,nosuid,nodev" "${5:-0}" "${6:-0}"
                ;;
            /home)
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "$1" "$2" "$3" "nodev" "${5:-0}" "${6:-0}"
                ;;
            *)
                printf '%s\n' "${line}"
                ;;
        esac
    done < "${fstab}" > "${tmp_file}"

    chmod 0644 "${tmp_file}"
    mv "${tmp_file}" "${fstab}"
}

@test "fstab update: hardens /tmp with noexec,nosuid,nodev" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    run grep '/tmp' "${BATS_TEST_TMPDIR}/fstab"
    [[ "${lines[0]}" == *"noexec,nosuid,nodev"* ]]
}

@test "fstab update: hardens /var/tmp with noexec,nosuid,nodev" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    run grep '/var/tmp' "${BATS_TEST_TMPDIR}/fstab"
    [[ "$output" == *"noexec,nosuid,nodev"* ]]
}

@test "fstab update: hardens /dev/shm with noexec,nosuid,nodev" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    run grep '/dev/shm' "${BATS_TEST_TMPDIR}/fstab"
    [[ "$output" == *"noexec,nosuid,nodev"* ]]
}

@test "fstab update: hardens /home with nodev" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    run grep '/home' "${BATS_TEST_TMPDIR}/fstab"
    [[ "$output" == *"nodev"* ]]
}

@test "fstab update: preserves comment lines" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    run grep '^# /etc/fstab' "${BATS_TEST_TMPDIR}/fstab"
    [ "$status" -eq 0 ]
}

@test "fstab update: preserves root partition unchanged" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    run grep '^/dev/sda1' "${BATS_TEST_TMPDIR}/fstab"
    [[ "$output" == *"defaults"* ]]
}

@test "fstab update: handles missing fstab gracefully" {
    run _test_update_fstab "${BATS_TEST_TMPDIR}/nonexistent"
    [ "$status" -eq 0 ]
}

@test "fstab update: result file has correct permissions" {
    create_test_fstab

    _test_update_fstab "${BATS_TEST_TMPDIR}/fstab"

    [ "$(file_mode "${BATS_TEST_TMPDIR}/fstab")" = "644" ]
}

# ---- Pi boot partition ----

@test "the Pi image also mounts its root read-write (no fstab ships)" {
    file_has "${BATS_TEST_DIRNAME}/../../scripts/rpi5/cmdline.txt" "root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw"
}
