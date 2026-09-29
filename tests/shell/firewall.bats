#!/usr/bin/env bats
# tests/shell/firewall.bats — tests for lib/firewall.sh rule builder

setup() {
    load test_helper
    load_security_lib "common"
    load_security_lib "firewall"
}

@test "_build_iptables_rules: generates valid strict ruleset with whitelist" {
    local config
    config=$(create_hardening_json)

    run _build_iptables_rules "${config}"
    [ "$status" -eq 0 ]

    # Check structure
    [[ "$output" == *"*filter"* ]]
    [[ "$output" == *":INPUT DROP [0:0]"* ]]
    [[ "$output" == *":FORWARD DROP [0:0]"* ]]
    [[ "$output" == *":OUTPUT ACCEPT [0:0]"* ]]
    [[ "$output" == *"-A INPUT -i lo -j ACCEPT"* ]]
    [[ "$output" == *"-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"* ]]
    [[ "$output" == *"-A INPUT -p tcp --dport 22 -j ACCEPT"* ]]
    [[ "$output" == *"-A OUTPUT -d api.kura.io -j ACCEPT"* ]]
    [[ "$output" == *"-A OUTPUT -d updates.kura.io -j ACCEPT"* ]]
    [[ "$output" == *"COMMIT"* ]]
}

@test "_build_iptables_rules: skips invalid domains in whitelist" {
    local config="${BATS_TEST_TMPDIR}/bad-whitelist.json"
    cat > "${config}" << 'JSON'
{
    "network_security": {
        "api_whitelist": ["valid.example.com", "__API_DOMAIN__", "also-valid.io"],
        "firewall_preset": "strict"
    }
}
JSON

    run _build_iptables_rules "${config}"
    [ "$status" -eq 0 ]

    # Valid domains included
    [[ "$output" == *"-A OUTPUT -d valid.example.com -j ACCEPT"* ]]
    [[ "$output" == *"-A OUTPUT -d also-valid.io -j ACCEPT"* ]]

    # Unresolved placeholder not in any OUTPUT rule
    [[ "$output" != *"-A OUTPUT -d __API_DOMAIN__"* ]]
}

@test "_build_iptables_rules: generates ruleset with empty whitelist" {
    local config="${BATS_TEST_TMPDIR}/empty-whitelist.json"
    cat > "${config}" << 'JSON'
{
    "network_security": {
        "api_whitelist": [],
        "firewall_preset": "strict"
    }
}
JSON

    run _build_iptables_rules "${config}"
    [ "$status" -eq 0 ]

    # Should still have base rules + COMMIT
    [[ "$output" == *"*filter"* ]]
    [[ "$output" == *"-A INPUT -p tcp --dport 22 -j ACCEPT"* ]]
    [[ "$output" == *"COMMIT"* ]]

    # No OUTPUT whitelist rules
    [[ "$output" != *"-A OUTPUT -d"* ]]
}

@test "apply_firewall: skips non-strict preset" {
    local config="${BATS_TEST_TMPDIR}/permissive.json"
    cat > "${config}" << 'JSON'
{
    "network_security": {
        "firewall_preset": "permissive",
        "api_whitelist": []
    }
}
JSON

    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping strict rules"* ]]
}

@test "_build_iptables_rules: ruleset ends with COMMIT" {
    local config
    config=$(create_hardening_json)

    run _build_iptables_rules "${config}"
    [ "$status" -eq 0 ]

    # Last non-empty line should be COMMIT
    local last_line
    last_line=$(echo "$output" | grep -v '^$' | tail -1)
    [ "${last_line}" = "COMMIT" ]
}

# Tomo: Traefik runs in a container and forwards to tomod on the host's port
# 3000. That traffic arrives from a Docker bridge and must be accepted; port
# 3000 must stay closed on every other interface. (grep, not [[ ]]: bash 3.2
# ignores a failing [[ ]] that is not a test's last command.)

@test "_build_iptables_rules: accepts tomod's port 3000 from Docker bridges" {
    run _build_iptables_rules "$(create_hardening_json)"
    [ "$status" -eq 0 ]
    grep -qxF -- "-A INPUT -i docker0 -p tcp --dport 3000 -j ACCEPT" <<< "$output"
    grep -qxF -- "-A INPUT -i br-+ -p tcp --dport 3000 -j ACCEPT" <<< "$output"
}

@test "_build_iptables_rules: port 3000 is not open on any other interface" {
    run _build_iptables_rules "$(create_hardening_json)"
    [ "$status" -eq 0 ]
    run grep -E -- "--dport 3000" <<< "$output"
    [ "${#lines[@]}" -eq 2 ]
    run grep -vE -- "-i (docker0|br-\+) " <<< "$output"
    [ "$status" -ne 0 ]
}
