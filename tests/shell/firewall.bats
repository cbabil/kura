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

# ---- Kura Desktop (ADR-023): HTTPS from the local network only ----

DESKTOP_V4="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16"
DESKTOP_V6="fe80::/10 fc00::/7"

@test "_build_iptables_rules: the desktop opens 443 to local IPv4 networks only" {
    run _build_iptables_rules 4 true
    [ "$status" -eq 0 ]
    for net in ${DESKTOP_V4}; do
        grep -qxF -- "-A INPUT -p tcp --dport 443 -s ${net} -j ACCEPT" <<< "$output"
    done
    [ "$(grep -c -- "--dport 443 .*-j ACCEPT$" <<< "$output")" -eq 4 ]
    run grep -F -- "fe80::" <<< "$output"
    [ "$status" -ne 0 ]
}

@test "_build_iptables_rules: the IPv6 ruleset opens 443 to link-local and ULA only" {
    run _build_iptables_rules 6 true
    [ "$status" -eq 0 ]
    for net in ${DESKTOP_V6}; do
        grep -qxF -- "-A INPUT -p tcp --dport 443 -s ${net} -j ACCEPT" <<< "$output"
    done
    run grep -F -- "192.168." <<< "$output"
    [ "$status" -ne 0 ]
}

@test "_build_iptables_rules: new desktop connections are rate-limited before the accepts" {
    run _build_iptables_rules 4 true
    local drop="-A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m recent --name desktop --update --seconds 60 --hitcount 121 -j DROP"
    local n_drop n_first
    n_drop=$(grep -nxF -- "${drop}" <<< "$output" | cut -d: -f1)
    n_first=$(grep -n -- "--dport 443 -s " <<< "$output" | head -1 | cut -d: -f1)
    [ -n "${n_drop}" ] && [ -n "${n_first}" ] && [ "${n_drop}" -lt "${n_first}" ]
}

@test "_build_iptables_rules: without the desktop, 443 stays closed in both families" {
    for family in 4 6; do
        run _build_iptables_rules "${family}" false
        [ "$status" -eq 0 ]
        run grep -F -- "--dport 443" <<< "$output"
        [ "$status" -ne 0 ]
    done
}

@test "apply_firewall: opens the desktop only when the config says it is installed" {
    local config="${BATS_TEST_TMPDIR}/hardening.json" calls="${BATS_TEST_TMPDIR}/calls"
    iptables-restore() { cat >> "${calls}.v4"; }
    ip6tables-restore() { cat >> "${calls}.v6"; }
    echo '{"network_security": {"firewall_preset": "strict", "desktop": true}}' > "${config}"
    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    grep -qF -- "-s 192.168.0.0/16" "${calls}.v4"
    grep -qF -- "-s fe80::/10" "${calls}.v6"
    rm -f "${calls}".*
    echo '{"network_security": {"firewall_preset": "strict"}}' > "${config}"
    run apply_firewall "${config}"
    run grep -F -- "--dport 443" "${calls}.v4" "${calls}.v6"
    [ "$status" -ne 0 ]
}

# ---- kura.local (ADR-030): mDNS from the local network only ----

@test "_build_iptables_rules: mDNS opens UDP 5353 to local networks only, in each family" {
    run _build_iptables_rules 4 false true
    [ "$status" -eq 0 ]
    for net in ${DESKTOP_V4}; do
        grep -qxF -- "-A INPUT -p udp --dport 5353 -s ${net} -j ACCEPT" <<< "$output"
    done
    run grep -F -- "--dport 443" <<< "$output"
    [ "$status" -ne 0 ]
}

@test "_build_iptables_rules: mDNS is not answered to containers' networks, and not over IPv6" {
    run _build_iptables_rules 4 false true
    # Docker's bridges use private ranges too: they are refused first
    local rules first_accept
    rules="$(grep -- "--dport 5353" <<< "$output")"
    [ "$(sed -n 1p <<< "${rules}")" = "-A INPUT -p udp --dport 5353 -i docker0 -j DROP" ]
    [ "$(sed -n 2p <<< "${rules}")" = "-A INPUT -p udp --dport 5353 -i br-+ -j DROP" ]
    [ "$(grep -c . <<< "${rules}")" -eq 6 ]
    [ "$(tail -n 1 <<< "$output")" = "COMMIT" ]
    # avahi publishes IPv4 addresses only (the ruleset lets no ICMPv6 in)
    run _build_iptables_rules 6 true true
    [ "$status" -eq 0 ]
    run grep -F -- "-p udp" <<< "$output"
    [ "$status" -ne 0 ]
}

@test "_build_iptables_rules: without mDNS, no UDP port is open" {
    for family in 4 6; do
        run _build_iptables_rules "${family}" true
        run grep -F -- "-p udp" <<< "$output"
        [ "$status" -ne 0 ]
    done
}

@test "apply_firewall: opens mDNS only when the config says so" {
    local config="${BATS_TEST_TMPDIR}/hardening.json" calls="${BATS_TEST_TMPDIR}/calls"
    iptables-restore() { cat >> "${calls}.v4"; }
    ip6tables-restore() { cat >> "${calls}.v6"; }
    echo '{"network_security": {"firewall_preset": "strict", "mdns": true}}' > "${config}"
    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    grep -qF -- "--dport 5353 -s 192.168.0.0/16" "${calls}.v4"
    run grep -F -- "5353" "${calls}.v6"
    [ "$status" -ne 0 ]
    rm -f "${calls}".*
    echo '{"network_security": {"firewall_preset": "strict", "mdns": false}}' > "${config}"
    run apply_firewall "${config}"
    run grep -F -- "5353" "${calls}.v4" "${calls}.v6"
    [ "$status" -ne 0 ]
}

@test "the default hardening turns mDNS on" {
    [ "$(jq -r '.network_security.mdns' "${BATS_TEST_DIRNAME}/../../packages/os-security/src/hardening.json")" = true ]
}

# ---- Remote Desktop (ADR-035) ----

@test "rdp_rules: the port from local networks, never from a container, and not without end" {
    run rdp_rules
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p <<< "$output")" = "INPUT -p tcp --dport 3389 -i docker0 -j DROP" ]
    [ "$(sed -n 2p <<< "$output")" = "INPUT -p tcp --dport 3389 -i br-+ -j DROP" ]
    # as for SSH: logins here are passwords, so a source that floods is dropped
    [ "$(sed -n 3p <<< "$output")" = "INPUT -p tcp --dport 3389 -m conntrack --ctstate NEW -m recent --name rdp --set" ]
    [ "$(sed -n 4p <<< "$output")" = "INPUT -p tcp --dport 3389 -m conntrack --ctstate NEW -m recent --name rdp --update --seconds 60 --hitcount 31 -j DROP" ]
    for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16; do
        grep -qxF -- "INPUT -p tcp --dport 3389 -s ${net} -j ACCEPT" <<< "$output"
    done
    [ "$(grep -c . <<< "$output")" -eq 8 ]
    # nothing accepts the port from anywhere
    run grep -E -- "--dport 3389 -j ACCEPT" <<< "$output"
    [ "$status" -ne 0 ]
}

# A rule the kernel refuses must cost Remote Desktop only, never the firewall
@test "_build_iptables_rules: the atomic ruleset never has Remote Desktop's rules" {
    for family in 4 6; do
        run _build_iptables_rules "${family}" true true
        run grep -F -- "3389" <<< "$output"
        [ "$status" -ne 0 ]
    done
}

@test "set_rdp_rules: on twice is each rule once, in order; off takes them all away" {
    fake_iptables
    set_rdp_rules on
    set_rdp_rules on
    [ "$(grep -c . "${RULES}")" -eq 8 ]
    [ "$(sort "${RULES}" | uniq -d | grep -c . || true)" -eq 0 ]
    # the refusals before the networks
    [ "$(head -1 "${RULES}")" = "INPUT -p tcp --dport 3389 -i docker0 -j DROP" ]
    # a copy left by an older version goes too
    echo "INPUT -p tcp --dport 3389 -s 10.0.0.0/8 -j ACCEPT" >> "${RULES}"
    set_rdp_rules off
    [ ! -s "${RULES}" ]
    # and every call waits for the lock
    run grep -v -- "^-w " "${RULES}.calls"
    [ "$status" -ne 0 ]
}

@test "set_rdp_rules: a rule that cannot be added fails, and nothing stays" {
    fake_iptables
    eval "real_$(declare -f iptables)"
    iptables() { case "$*" in *"-A INPUT"*169.254*) return 1 ;; esac; real_iptables "$@"; }
    run set_rdp_rules on
    [ "$status" -ne 0 ]
    [ ! -s "${RULES}" ]
}

@test "set_rdp_rules: off fails when a rule cannot be taken out" {
    fake_iptables
    set_rdp_rules on
    eval "real_$(declare -f iptables)"
    iptables() { [ "$2" != "-D" ] && real_iptables "$@"; }
    run set_rdp_rules off
    [ "$status" -ne 0 ]
}

@test "apply_firewall: Remote Desktop's rules only when the config says so, and never fatal" {
    local config="${BATS_TEST_TMPDIR}/hardening.json"
    iptables-restore() { cat > /dev/null; }
    ip6tables-restore() { cat > /dev/null; }
    fake_iptables
    echo '{"network_security": {"firewall_preset": "strict"}}' > "${config}"
    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    [ ! -s "${RULES}" ]
    echo '{"network_security": {"firewall_preset": "strict", "rdp": true}}' > "${config}"
    apply_firewall "${config}"
    grep -qxF -- "INPUT -p tcp --dport 3389 -s 192.168.0.0/16 -j ACCEPT" "${RULES}"
    iptables() { return 1; }
    run apply_firewall "${config}"
    [ "$status" -eq 0 ]
    output_has "Remote Desktop"
}

# Without the strict ruleset nothing of the firewall is Kura's, these rules
# included: xrdp's own list of local networks (its drop-in) is what is left
@test "apply_firewall: with another preset, nothing is touched" {
    local config="${BATS_TEST_TMPDIR}/hardening.json"
    iptables-restore() { echo restored >> "${BATS_TEST_TMPDIR}/restored"; }
    fake_iptables
    echo '{"network_security": {"firewall_preset": "none", "rdp": true}}' > "${config}"
    apply_firewall "${config}"
    [ ! -e "${BATS_TEST_TMPDIR}/restored" ]
    [ ! -e "${RULES}.calls" ]
}
