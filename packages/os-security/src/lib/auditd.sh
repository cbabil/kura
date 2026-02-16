#!/bin/bash
# lib/auditd.sh — audit rule deployment

apply_audit_rules() {
    local rules_dir="/etc/audit/rules.d"
    mkdir -p "${rules_dir}"

    local rules_path="${rules_dir}/__BRAND__.rules"

    cat <<'EOF' | write_file "${rules_path}"
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudo_actions
-w /var/log/auth.log -p wa -k auth_logs
-a always,exit -F arch=b64 -S execve -k exec_calls
EOF

    if ! auditctl -R "${rules_path}" 2>/dev/null; then
        log_error "Failed to load audit rules -- auditing NOT active"
    fi
}
