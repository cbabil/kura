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

# ---- Stubs ----
# stub_curl_copy <src>: curl stub that "downloads" <src> to its -o path and
# records the requested URL in ${BATS_TEST_TMPDIR}/curl-url.
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
        echo "${url}" > "${BATS_TEST_TMPDIR}/curl-url"
        cp "${CURL_SRC}" "${out}"
    }
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
        "api_whitelist": ["api.kura.io", "updates.kura.io"],
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
