#!/usr/bin/env bats
# tests/shell/device-config.bats — the config files the image ships under
# /etc/<brand>/ match what reads them: os-config (config.json) and the
# supervisor (supervisor-config.json, security/hardening.json).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
OVERLAY="${REPO_ROOT}/overlay/common/etc/kura"

setup() { load test_helper; }

@test "supervisor-config.json ships in the overlay, valid, with an empty applications list" {
    [ -f "${OVERLAY}/supervisor-config.json" ]
    run jq -e '.applications == []' "${OVERLAY}/supervisor-config.json"
    [ "$status" -eq 0 ]
}

@test "config.json holds only what os-config reads, plus the version the login banner shows" {
    run jq -e '.hostname and .networkConfig.ethernet and .networkConfig.wifi and has("version")' \
        "${OVERLAY}/config.json"
    [ "$status" -eq 0 ]
    run jq -e 'has("supervisor") or has("containerAPI") or has("updates") or has("logging")' \
        "${OVERLAY}/config.json"
    [ "$status" -ne 0 ]
}

@test "the dead package copy of config.json is gone and no longer installed" {
    [ ! -e "${REPO_ROOT}/packages/os-config/src/config.json" ]
    run grep -n "config.json" "${REPO_ROOT}/scripts/common/install-os-pkgs.sh"
    [ "$status" -ne 0 ]
}

@test "hardening.json has the sections the supervisor's security config expects" {
    run jq -e '.container_security.allowed_registries and .update_security' \
        "${REPO_ROOT}/packages/os-security/src/hardening.json"
    [ "$status" -eq 0 ]
}
