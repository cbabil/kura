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
