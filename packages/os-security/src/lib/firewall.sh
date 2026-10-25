#!/bin/bash
# lib/firewall.sh — atomic iptables firewall via iptables-restore

apply_firewall() {
    local config_file="$1"

    local preset
    preset=$(jq -r '.network_security.firewall_preset // "strict"' "${config_file}")

    if [[ "${preset}" != "strict" ]]; then
        log_info "Firewall preset is '${preset}', skipping strict rules"
        return 0
    fi

    local ruleset
    ruleset=$(_build_iptables_rules)

    # Apply IPv4 rules atomically
    if ! printf '%s' "${ruleset}" | iptables-restore 2>/dev/null; then
        log_error "Failed to apply IPv4 firewall rules"
        return 1
    fi
    log_info "IPv4 firewall rules applied"

    # Apply equivalent IPv6 rules atomically
    if ! printf '%s' "${ruleset}" | ip6tables-restore 2>/dev/null; then
        log_warning "Failed to apply IPv6 firewall rules"
    else
        log_info "IPv6 firewall rules applied"
    fi
}

# Inbound: SSH only. Ports published by containers reach them through Docker's
# own FORWARD rules, added when dockerd starts after this ruleset (os-security
# runs before sysinit.target).
_build_iptables_rules() {
    cat <<'RULES'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
COMMIT
RULES
}
