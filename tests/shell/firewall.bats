#!/usr/bin/env bats
# tests/shell/firewall.bats — tests for lib/firewall.sh rule builder

setup() {
    load test_helper
    load_security_lib "common"
    load_security_lib "firewall"
}

# (grep, not [[ ]]: bash 3.2 ignores a failing [[ ]] that is not a test's
# last command.)

@test "_build_iptables_rules: strict ruleset, drop by default, outbound open" {
    run _build_iptables_rules
    [ "$status" -eq 0 ]
    for rule in "*filter" ":INPUT DROP [0:0]" ":FORWARD DROP [0:0]" ":OUTPUT ACCEPT [0:0]" \
                "-A INPUT -i lo -j ACCEPT" \
                "-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"; do
        grep -qxF -- "${rule}" <<< "$output"
    done
    [ "$(grep -v '^$' <<< "$output" | tail -1)" = "COMMIT" ]
}

# Inbound, only SSH is opened; Docker adds its own FORWARD rules for published
# ports.
@test "_build_iptables_rules: SSH is the only inbound port opened" {
    run _build_iptables_rules
    [ "$status" -eq 0 ]
    run grep -E -- "^-A INPUT .*--dport" <<< "$output"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "-A INPUT -p tcp --dport 22 -j ACCEPT" ]
}

@test "apply_firewall: skips non-strict preset" {
    local config="${BATS_TEST_TMPDIR}/permissive.json"
    echo '{"network_security": {"firewall_preset": "permissive"}}' > "${config}"
    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    output_has "skipping strict rules"
}
