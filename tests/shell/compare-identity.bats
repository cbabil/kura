#!/usr/bin/env bats
# tests/shell/compare-identity.bats — tests for tests/boot/compare-identity.sh
# (two boots of the same image must produce different device identities)

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SCRIPT="${REPO_ROOT}/tests/boot/compare-identity.sh"

setup() {
    load test_helper
    A="${BATS_TEST_TMPDIR}/a.txt"
    B="${BATS_TEST_TMPDIR}/b.txt"
    printf 'ssh_host_key SHA256:aaa\nmachine_id 111\n' > "${A}"
    printf 'ssh_host_key SHA256:bbb\nmachine_id 222\n' > "${B}"
}

@test "compare-identity: passes when every value differs" {
    run "${SCRIPT}" "${A}" "${B}"
    [ "$status" -eq 0 ]
    output_has "PASS ssh_host_key"
    output_has "PASS machine_id"
}

@test "compare-identity: fails and names a value shared by both boots" {
    printf 'ssh_host_key SHA256:bbb\nmachine_id 111\n' > "${B}"
    run "${SCRIPT}" "${A}" "${B}"
    [ "$status" -eq 1 ]
    output_has "FAIL machine_id"
    output_has "PASS ssh_host_key"
}

@test "compare-identity: fails when a value is missing from a boot" {
    printf 'ssh_host_key SHA256:bbb\n' > "${B}"
    run "${SCRIPT}" "${A}" "${B}"
    [ "$status" -eq 1 ]
    output_has "FAIL machine_id"
}

@test "compare-identity: fails when a report is missing" {
    run "${SCRIPT}" "${A}" "${BATS_TEST_TMPDIR}/missing.txt"
    [ "$status" -eq 1 ]
    output_has "not found"
}
