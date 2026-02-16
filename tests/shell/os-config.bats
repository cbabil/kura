#!/usr/bin/env bats
# tests/shell/os-config.bats — tests for os-config SSID validation and WiFi config

setup() {
    load test_helper
    # Define the SSID regex (same as os-config)
    SAFE_SSID_RE='^[a-zA-Z0-9][a-zA-Z0-9 _.-]*$'
}

# ---- SSID validation (regex) ----

@test "SSID regex: accepts simple alphanumeric" {
    [[ "MyNetwork" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: accepts SSID with spaces" {
    [[ "My WiFi Network" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: accepts SSID with hyphens" {
    [[ "Office-5G" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: accepts SSID with underscores" {
    [[ "Home_Network" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: accepts SSID with dots" {
    [[ "My.Network" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: accepts SSID starting with digit" {
    [[ "5G-Home" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects empty string" {
    ! [[ "" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID starting with space" {
    ! [[ " BadSSID" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID starting with hyphen" {
    ! [[ "-BadSSID" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID starting with dot" {
    ! [[ ".hidden" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID with semicolon (injection)" {
    ! [[ "net;cmd" =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID with backtick" {
    ! [[ 'net`id`' =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID with dollar sign" {
    ! [[ 'net$HOME' =~ ${SAFE_SSID_RE} ]]
}

@test "SSID regex: rejects SSID with newline" {
    ! [[ $'net\ncmd' =~ ${SAFE_SSID_RE} ]]
}

# ---- WiFi config generation ----

@test "setup_wifi: generates valid NM connection file" {
    local config
    config=$(create_config_json)
    local nm_dir="${BATS_TEST_TMPDIR}/nm-connections"
    mkdir -p "${nm_dir}"

    # Source os-config functions (with brand resolved and paths overridden)
    local src="${BATS_TEST_DIRNAME}/../../packages/os-config/src/os-config"
    local tmp="${BATS_TEST_TMPDIR}/os-config-funcs.sh"
    sed -e 's|__BRAND__|falken|g' \
        -e "s|CONFIG_PATH=.*|CONFIG_PATH=\"${config}\"|" \
        -e "s|NM_CONN_DIR=.*|NM_CONN_DIR=\"${nm_dir}\"|" \
        -e '/^while true/,/^done$/d' \
        -e '/^set -euo pipefail$/d' \
        "${src}" > "${tmp}"
    # shellcheck disable=SC1090
    source "${tmp}"

    setup_wifi

    # Check MyNetwork connection file exists
    [ -f "${nm_dir}/MyNetwork.nmconnection" ]
    run cat "${nm_dir}/MyNetwork.nmconnection"
    [[ "$output" == *"id=MyNetwork"* ]]
    [[ "$output" == *"type=wifi"* ]]
    [[ "$output" == *"ssid=MyNetwork"* ]]
    [[ "$output" == *"key-mgmt=wpa-psk"* ]]
    [[ "$output" == *"psk=secret123"* ]]
    [[ "$output" == *"interface-name=wlan0"* ]]

    # Check Office-5G too
    [ -f "${nm_dir}/Office-5G.nmconnection" ]
}

@test "setup_wifi: sets 0600 permissions on connection files" {
    local config
    config=$(create_config_json)
    local nm_dir="${BATS_TEST_TMPDIR}/nm-connections2"
    mkdir -p "${nm_dir}"

    local src="${BATS_TEST_DIRNAME}/../../packages/os-config/src/os-config"
    local tmp="${BATS_TEST_TMPDIR}/os-config-funcs2.sh"
    sed -e 's|__BRAND__|falken|g' \
        -e "s|CONFIG_PATH=.*|CONFIG_PATH=\"${config}\"|" \
        -e "s|NM_CONN_DIR=.*|NM_CONN_DIR=\"${nm_dir}\"|" \
        -e '/^while true/,/^done$/d' \
        -e '/^set -euo pipefail$/d' \
        "${src}" > "${tmp}"
    source "${tmp}"

    setup_wifi

    # Check permissions (macOS: stat -f, Linux: stat -c)
    if stat -f '%Lp' "${nm_dir}/MyNetwork.nmconnection" >/dev/null 2>&1; then
        perms=$(stat -f '%Lp' "${nm_dir}/MyNetwork.nmconnection")
    else
        perms=$(stat -c '%a' "${nm_dir}/MyNetwork.nmconnection")
    fi
    [ "${perms}" = "600" ]
}

@test "setup_wifi: skips invalid SSIDs" {
    local config="${BATS_TEST_TMPDIR}/bad-ssid-config.json"
    cat > "${config}" << 'JSON'
{
    "hostname": "test",
    "networkConfig": {
        "wifi": {
            "enable": true,
            "defaultInterface": "wlan0",
            "networks": [
                {"ssid": "GoodNetwork", "psk": "pass1"},
                {"ssid": ";evil", "psk": "pass2"},
                {"ssid": "", "psk": "pass3"}
            ]
        }
    }
}
JSON

    local nm_dir="${BATS_TEST_TMPDIR}/nm-bad-ssid"
    mkdir -p "${nm_dir}"

    local src="${BATS_TEST_DIRNAME}/../../packages/os-config/src/os-config"
    local tmp="${BATS_TEST_TMPDIR}/os-config-funcs3.sh"
    sed -e 's|__BRAND__|falken|g' \
        -e "s|CONFIG_PATH=.*|CONFIG_PATH=\"${config}\"|" \
        -e "s|NM_CONN_DIR=.*|NM_CONN_DIR=\"${nm_dir}\"|" \
        -e '/^while true/,/^done$/d' \
        -e '/^set -euo pipefail$/d' \
        "${src}" > "${tmp}"
    source "${tmp}"

    setup_wifi

    # Good SSID created
    [ -f "${nm_dir}/GoodNetwork.nmconnection" ]
    # Bad SSIDs not created
    [ ! -f "${nm_dir}/;evil.nmconnection" ]
    [ ! -f "${nm_dir}/.nmconnection" ]
}

@test "setup_wifi: does nothing when wifi disabled" {
    local config="${BATS_TEST_TMPDIR}/wifi-off.json"
    cat > "${config}" << 'JSON'
{
    "hostname": "test",
    "networkConfig": {
        "wifi": {
            "enable": false,
            "networks": [{"ssid": "NoCreate", "psk": "pass"}]
        }
    }
}
JSON

    local nm_dir="${BATS_TEST_TMPDIR}/nm-disabled"
    mkdir -p "${nm_dir}"

    local src="${BATS_TEST_DIRNAME}/../../packages/os-config/src/os-config"
    local tmp="${BATS_TEST_TMPDIR}/os-config-funcs4.sh"
    sed -e 's|__BRAND__|falken|g' \
        -e "s|CONFIG_PATH=.*|CONFIG_PATH=\"${config}\"|" \
        -e "s|NM_CONN_DIR=.*|NM_CONN_DIR=\"${nm_dir}\"|" \
        -e '/^while true/,/^done$/d' \
        -e '/^set -euo pipefail$/d' \
        "${src}" > "${tmp}"
    source "${tmp}"

    setup_wifi

    # No files created
    [ "$(ls -A "${nm_dir}" 2>/dev/null)" = "" ]
}
