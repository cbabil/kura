#!/usr/bin/env bats
# tests/shell/device-config.bats — the config files the image ships under
# /etc/<brand>/ match what reads them: os-config (config.json) and
# os-security (security/hardening.json).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
OVERLAY="${REPO_ROOT}/overlay/common/etc/kura"

setup() { load test_helper; }

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

@test "hardening.json holds only what os-security reads" {
    run jq -e 'keys == ["network_security"] and (.network_security | keys) == ["firewall_preset"]' \
        "${REPO_ROOT}/packages/os-security/src/hardening.json"
    [ "$status" -eq 0 ]
}

@test "NetworkManager does not phone home for connectivity checks" {
    run grep -q "connectivity\|__BRAND_API__" "${REPO_ROOT}/packages/os-config/src/00-os-network.conf"
    [ "$status" -ne 0 ]
}
