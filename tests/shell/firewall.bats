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
    [ -z "$(grep -E -- "^-A INPUT .*--dport" <<< "$output" | grep -v -- "--dport 22 ")" ]
    [ "$(grep -E -- "-j ACCEPT$" <<< "$output" | grep -c -- "--dport")" -eq 1 ]
    grep -qxF -- "-A INPUT -p tcp --dport 22 -j ACCEPT" <<< "$output"
}

# A source opening more than 60 new SSH connections a minute is dropped,
# before the ACCEPT (a flood guard: OpenSSH's PerSourcePenalties already slows
# sources that fail to log in); established sessions match ESTABLISHED first.
@test "_build_iptables_rules: new SSH connections are rate-limited per source" {
    run _build_iptables_rules
    [ "$status" -eq 0 ]
    local set="-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --name ssh --set"
    local drop="-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --name ssh --update --seconds 60 --hitcount 61 -j DROP"
    local accept="-A INPUT -p tcp --dport 22 -j ACCEPT"
    local n_set n_drop n_accept
    n_set=$(grep -nxF -- "${set}" <<< "$output" | cut -d: -f1)
    n_drop=$(grep -nxF -- "${drop}" <<< "$output" | cut -d: -f1)
    n_accept=$(grep -nxF -- "${accept}" <<< "$output" | cut -d: -f1)
    [ -n "${n_set}" ] && [ -n "${n_drop}" ] && [ -n "${n_accept}" ]
    [ "${n_set}" -lt "${n_drop}" ] && [ "${n_drop}" -lt "${n_accept}" ]
}

@test "apply_firewall: skips non-strict preset" {
    local config="${BATS_TEST_TMPDIR}/permissive.json"
    echo '{"network_security": {"firewall_preset": "permissive"}}' > "${config}"
    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    output_has "skipping strict rules"
}
