#!/bin/bash
# tests/shell/test_helper.bash — shared setup for bats tests

FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

# ---- Assertions ----
# bash 3.2 (macOS) ignores a failing [[ ]] that is not the last command in a
# test, so pattern checks go through these functions (plain commands fail
# correctly on every bash).
output_has() { [[ "$output" == *"$1"* ]]; }
matches() { [[ "$1" == $2 ]]; }
file_has() { grep -qF -- "$2" "$1"; }

# file_mode <file>: permission bits in octal (macOS: stat -f, Linux: stat -c)
file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

# ---- Stubs ----
# log_call <words...>: record a stubbed command in ${CALLS}
log_call() { echo "$*" >> "${CALLS}"; }

# stub_disk_tools <root-device> <parent-disk>: findmnt/lsblk for "/"
stub_disk_tools() {
    ROOT_DEV="$1"; PARENT="$2"
    findmnt() { echo "${ROOT_DEV}"; }
    lsblk() { echo "${PARENT}"; }
}

# stub_curl_copy <src>: curl stub that "downloads" <src> to its -o path and
# appends each requested URL to ${BATS_TEST_TMPDIR}/curl-url.
stub_curl_copy() {
    CURL_SRC="$1"
    curl() {
        local out="" url=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift ;;
                http*) url="$1" ;;
            esac
            shift
        done
        echo "${url}" >> "${BATS_TEST_TMPDIR}/curl-url"
        cp "${CURL_SRC}" "${out}"
    }
}

# load_os_config <config> <nm-dir> [hosts]: source os-config's functions
# with its paths pointed at test files and nmcli stubbed
load_os_config() {
    local src="${BATS_TEST_DIRNAME}/../../packages/os-config/src/os-config"
    local tmp="${BATS_TEST_TMPDIR}/os-config-funcs.sh"
    sed -e 's|__BRAND__|kura|g' \
        -e "s|^CONFIG_PATH=.*|CONFIG_PATH=\"$1\"|" \
        -e "s|^NM_CONN_DIR=.*|NM_CONN_DIR=\"$2\"|" \
        -e "s|^HOSTS_PATH=.*|HOSTS_PATH=\"${3:-${BATS_TEST_TMPDIR}/hosts}\"|" \
        -e '/^while true/,/^done$/d' \
        -e '/^set -euo pipefail$/d' \
        "${src}" > "${tmp}"
    # shellcheck disable=SC1090
    source "${tmp}"
    nmcli() { echo "nmcli $*" >> "${BATS_TEST_TMPDIR}/nmcli-calls"; }
}

# Source security lib with __BRAND__ resolved to "kura" for testing.
# Each lib file is loaded via a temp copy with placeholders replaced.
load_security_lib() {
    local lib_name="$1"
    local src="${BATS_TEST_DIRNAME}/../../packages/os-security/src/lib/${lib_name}.sh"
    local tmp="${BATS_TEST_TMPDIR}/${lib_name}.sh"
    sed 's|__BRAND__|kura|g' "${src}" > "${tmp}"
    # shellcheck disable=SC1090
    source "${tmp}"
}

# Create a temporary hardening.json fixture
create_hardening_json() {
    local dest="${1:-${BATS_TEST_TMPDIR}/hardening.json}"
    cat > "${dest}" << 'JSON'
{
    "network_security": {
        "firewall_preset": "strict"
    },
    "apparmor_profiles": [
        {"name": "test-profile", "content": "profile test {}"}
    ],
    "seccomp_profiles": [
        {"name": "test-seccomp", "rules": {"defaultAction": "SCMP_ACT_ALLOW"}}
    ]
}
JSON
    echo "${dest}"
}

# Create a temporary config.json for os-config tests
create_config_json() {
    local dest="${1:-${BATS_TEST_TMPDIR}/config.json}"
    cat > "${dest}" << 'JSON'
{
    "hostname": "test-device",
    "networkConfig": {
        "wifi": {
            "enable": true,
            "defaultInterface": "wlan0",
            "networks": [
                {"ssid": "MyNetwork", "psk": "secret123"},
                {"ssid": "Office-5G", "psk": "pass456"}
            ]
        },
        "ethernet": {
            "enable": true,
            "defaultInterface": "eth0"
        }
    }
}
JSON
    echo "${dest}"
}

# Create a temporary fstab
create_test_fstab() {
    local dest="${1:-${BATS_TEST_TMPDIR}/fstab}"
    cat > "${dest}" << 'FSTAB'
# /etc/fstab
/dev/sda1	/	ext4	defaults	0	1
tmpfs	/tmp	tmpfs	defaults	0	0
tmpfs	/var/tmp	tmpfs	defaults	0	0
tmpfs	/dev/shm	tmpfs	defaults	0	0
/dev/sda2	/home	ext4	defaults	0	2
FSTAB
    echo "${dest}"
}
