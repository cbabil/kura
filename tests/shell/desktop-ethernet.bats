#!/usr/bin/env bats
# tests/shell/desktop-ethernet.bats — os-config's Ethernet address, which
# Kura Desktop's Settings sets through config.json (ADR-029).

setup() {
    load test_helper
    NM_DIR="${BATS_TEST_TMPDIR}/nm"; mkdir -p "${NM_DIR}"
    CFG="${BATS_TEST_TMPDIR}/cfg.json"
    CONN="${NM_DIR}/kura-ethernet.nmconnection"
}

manual() { echo '{"hostname":"kura","networkConfig":{"ethernet":{"enable":true,"ipv4":{"method":"manual","address":"192.168.1.50/24","gateway":"192.168.1.1","dns":["192.168.1.1","9.9.9.9"]}}}}' > "${CFG}"; }

@test "os-config: a manual Ethernet address becomes a NetworkManager connection" {
    manual
    load_os_config "${CFG}" "${NM_DIR}"
    setup_ethernet
    [ "$(file_mode "${CONN}")" = 600 ]
    file_has "${CONN}" "type=ethernet"
    file_has "${CONN}" "method=manual"
    file_has "${CONN}" "address1=192.168.1.50/24,192.168.1.1"
    file_has "${CONN}" "dns=192.168.1.1;9.9.9.9;"
    file_has "${BATS_TEST_TMPDIR}/nmcli-calls" "connection reload"
}

@test "os-config: back to auto keeps Kura's connection, now asking the network for an address" {
    manual
    load_os_config "${CFG}" "${NM_DIR}"
    setup_ethernet
    echo '{"hostname":"kura","networkConfig":{"ethernet":{"enable":true,"ipv4":{"method":"auto"}}}}' > "${CFG}"
    setup_ethernet
    file_has "${CONN}" "method=auto"
    ! grep -q "address1" "${CONN}"
}

@test "os-config: a device never given an address by Kura keeps NetworkManager's own connection" {
    echo '{"hostname":"kura","networkConfig":{"ethernet":{"enable":true}}}' > "${CFG}"
    load_os_config "${CFG}" "${NM_DIR}"
    setup_ethernet
    [ ! -e "${CONN}" ]
}

@test "os-config: a manual address that is not one is not written" {
    echo '{"networkConfig":{"ethernet":{"ipv4":{"method":"manual","address":"x; rm -rf /","gateway":"192.168.1.1","dns":[]}}}}' > "${CFG}"
    load_os_config "${CFG}" "${NM_DIR}"
    setup_ethernet
    [ ! -e "${CONN}" ]
}
