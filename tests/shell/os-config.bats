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

# wifi_config <networks-json>: a config.json with Wi-Fi on and these networks
wifi_config() {
    local config="${BATS_TEST_TMPDIR}/wifi-config.json"
    echo "{\"networkConfig\":{\"wifi\":{\"enable\":true,\"defaultInterface\":\"wlan0\",\"networks\":$1}}}" \
        > "${config}"
    echo "${config}"
}

setup_nm() { NM_DIR="${BATS_TEST_TMPDIR}/nm"; mkdir -p "${NM_DIR}"; }

@test "setup_wifi: generates valid NM connection files, private to root" {
    setup_nm
    load_os_config "$(create_config_json)" "${NM_DIR}"
    setup_wifi
    local f="${NM_DIR}/MyNetwork.nmconnection"
    for line in "id=MyNetwork" "type=wifi" "ssid=MyNetwork" "key-mgmt=wpa-psk" \
                "psk=secret123" "interface-name=wlan0"; do
        file_has "${f}" "${line}"
    done
    [ -f "${NM_DIR}/Office-5G.nmconnection" ]
    [ "$(file_mode "${f}")" = "600" ]
}

@test "setup_wifi: skips invalid SSIDs" {
    setup_nm
    load_os_config "$(wifi_config '[{"ssid":"GoodNetwork","psk":"pass1"},{"ssid":";evil","psk":"pass2"},{"ssid":"","psk":"pass3"}]')" "${NM_DIR}"
    setup_wifi
    [ -f "${NM_DIR}/GoodNetwork.nmconnection" ]
    [ ! -f "${NM_DIR}/;evil.nmconnection" ]
    [ ! -f "${NM_DIR}/.nmconnection" ]
}

@test "setup_wifi: does nothing when wifi disabled" {
    setup_nm
    local config="${BATS_TEST_TMPDIR}/wifi-off.json"
    echo '{"networkConfig":{"wifi":{"enable":false,"networks":[{"ssid":"NoCreate","psk":"pass"}]}}}' > "${config}"
    load_os_config "${config}" "${NM_DIR}"
    setup_wifi
    [ ! -f "${NM_DIR}/NoCreate.nmconnection" ]
}

@test "setup_wifi: marks a hidden network so NetworkManager probes for it" {
    setup_nm
    load_os_config "$(wifi_config '[{"ssid":"Attic","psk":"pass1234","hidden":true},{"ssid":"Open","psk":"pass5678"}]')" "${NM_DIR}"
    setup_wifi
    file_has "${NM_DIR}/Attic.nmconnection" "hidden=true"
    run grep -q "hidden=" "${NM_DIR}/Open.nmconnection"
    [ "$status" -ne 0 ]
}

@test "setup_wifi: escapes the key the way NetworkManager's keyfiles read it" {
    setup_nm
    load_os_config "$(wifi_config '[{"ssid":"Home","psk":" pa\\ss "}]')" "${NM_DIR}"
    setup_wifi
    file_has "${NM_DIR}/Home.nmconnection" 'psk=\spa\\ss\s'
}

@test "setup_wifi: reloads NetworkManager only when a connection file changed" {
    setup_nm
    load_os_config "$(create_config_json)" "${NM_DIR}"
    setup_wifi
    setup_wifi
    [ "$(grep -c "nmcli connection reload" "${BATS_TEST_TMPDIR}/nmcli-calls")" -eq 1 ]
}

@test "os-config.service does not wait for the network to be online" {
    local unit="${BATS_TEST_DIRNAME}/../../packages/os-config/src/os-config.service"
    file_has "${unit}" "After=NetworkManager.service"
    run grep -q "network-online" "${unit}"
    [ "$status" -ne 0 ]
}

# ---- hostname ----

@test "apply_hostname: sets the hostname and the 127.0.1.1 entry in /etc/hosts" {
    local hosts="${BATS_TEST_TMPDIR}/hosts"
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tkura\n' > "${hosts}"
    load_os_config "$(create_config_json)" "${BATS_TEST_TMPDIR}/nm" "${hosts}"
    hostname() { echo kura; }
    hostnamectl() { echo "hostnamectl $*" >> "${BATS_TEST_TMPDIR}/calls"; }
    apply_hostname
    file_has "${BATS_TEST_TMPDIR}/calls" "hostnamectl set-hostname test-device"
    file_has "${hosts}" "127.0.1.1	test-device"
    file_has "${hosts}" "127.0.0.1	localhost"
}
