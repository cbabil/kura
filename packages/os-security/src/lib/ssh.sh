#!/bin/bash
# lib/ssh.sh — SSH hardening via drop-in config

apply_ssh_hardening() {
    local dropin_dir="/etc/ssh/sshd_config.d"
    mkdir -p "${dropin_dir}"

    cat <<'EOF' | write_file "${dropin_dir}/99-hardening.conf"
PermitRootLogin prohibit-password
X11Forwarding no
MaxAuthTries 3
AllowAgentForwarding no
AllowTcpForwarding no
PrintLastLog yes
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

    log_info "SSH hardening config written (applied on next sshd start)"
}
