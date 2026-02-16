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
    ruleset=$(_build_iptables_rules "${config_file}")

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

_build_iptables_rules() {
    local config_file="$1"
    local lines
    lines="*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT"

    local count domain
    count=$(jq '.network_security.api_whitelist | length' "${config_file}" 2>/dev/null)

    local i
    for ((i = 0; i < count; i++)); do
        domain=$(jq -r ".network_security.api_whitelist[${i}]" "${config_file}")
        if validate_domain "${domain}"; then
            lines="${lines}
-A OUTPUT -d ${domain} -j ACCEPT"
        else
            log_warning "Skipping invalid whitelist domain: ${domain}"
        fi
    done

    lines="${lines}
COMMIT"
    printf '%s\n' "${lines}"
}
