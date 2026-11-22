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

    local desktop mdns
    desktop=$(jq -r '.network_security.desktop == true' "${config_file}")
    mdns=$(jq -r '.network_security.mdns == true' "${config_file}")

    # Apply IPv4 rules atomically
    if ! _build_iptables_rules 4 "${desktop}" "${mdns}" | iptables-restore 2>/dev/null; then
        log_error "Failed to apply IPv4 firewall rules"
        return 1
    fi
    log_info "IPv4 firewall rules applied"

    # Apply the IPv6 equivalent atomically
    if ! _build_iptables_rules 6 "${desktop}" "${mdns}" | ip6tables-restore 2>/dev/null; then
        log_warning "Failed to apply IPv6 firewall rules"
    else
        log_info "IPv6 firewall rules applied"
    fi
}

# Local networks Kura Desktop answers (ADR-023): private, link-local, ULA
DESKTOP_NETS_4="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16"
DESKTOP_NETS_6="fe80::/10 fc00::/7"

# _build_iptables_rules [family 4|6] [desktop true|false] [mdns true|false]
# Inbound: SSH, at most 60 new connections a minute per source (a flood
# guard: OpenSSH 10's PerSourcePenalties already slows sources whose logins
# fail; open sessions match ESTABLISHED first). When Kura Desktop is
# installed, HTTPS on 443 from local networks only, at most 120 new
# connections a minute per source. Ports published by containers reach them
# through Docker's own FORWARD rules, added when dockerd starts after this
# ruleset (os-security runs before sysinit.target). With mDNS (ADR-030),
# UDP 5353 from the same local networks over IPv4, so the device answers to
# <host>.local; nothing else is open over UDP. Docker's bridges use private
# ranges too, so they are refused first; and avahi publishes no IPv6
# address, since no ICMPv6 comes in here.
_build_iptables_rules() {
    local family="${1:-4}" desktop="${2:-false}" mdns="${3:-false}" nets net
    nets="${DESKTOP_NETS_4}"
    [ "${family}" = "6" ] && nets="${DESKTOP_NETS_6}"
    cat <<'RULES'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --name ssh --set
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --name ssh --update --seconds 60 --hitcount 61 -j DROP
-A INPUT -p tcp --dport 22 -j ACCEPT
RULES
    if [ "${desktop}" = "true" ]; then
        echo "-A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m recent --name desktop --set"
        echo "-A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m recent --name desktop --update --seconds 60 --hitcount 121 -j DROP"
        for net in ${nets}; do
            echo "-A INPUT -p tcp --dport 443 -s ${net} -j ACCEPT"
        done
    fi
    if [ "${mdns}" = "true" ] && [ "${family}" = "4" ]; then
        echo "-A INPUT -p udp --dport 5353 -i docker0 -j DROP"
        echo "-A INPUT -p udp --dport 5353 -i br-+ -j DROP"
        for net in ${nets}; do
            echo "-A INPUT -p udp --dport 5353 -s ${net} -j ACCEPT"
        done
    fi
    echo "COMMIT"
}
