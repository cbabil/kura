#!/usr/bin/env bats
# tests/shell/boot-setup-file.bats — the kura-setup.json the boot tests put
# on the image (tests/boot/boot-checks.sh, make_setup_file) must pass first
# boot's own validation, so a CI boot fails on Kura, never on its test data.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    KEY="${BATS_TEST_TMPDIR}/id_ed25519"
    LOGIN_PASS="Kura-test"
    SSH_PORT=2222
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/tests/boot/boot-checks.sh"
    SETUP_BRAND=kura SETUP_ROOT="${BATS_TEST_TMPDIR}/root"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/firstboot-setup-check.sh"
    getent() { return 2; }   # no account clashes with the new user
}

@test "make_setup_file: the Server layout's file is valid, with the desktop on" {
    LAYOUT=server make_setup_file "${BATS_TEST_TMPDIR}/s.json"
    run validate_setup "${BATS_TEST_TMPDIR}/s.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r .desktop "${BATS_TEST_TMPDIR}/s.json")" = "true" ]
}

@test "make_setup_file: the full layout's file is valid, and can turn the desktop off" {
    LAYOUT=full DESKTOP=false make_setup_file "${BATS_TEST_TMPDIR}/s.json"
    run validate_setup "${BATS_TEST_TMPDIR}/s.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r .desktop "${BATS_TEST_TMPDIR}/s.json")" = "false" ]
}
