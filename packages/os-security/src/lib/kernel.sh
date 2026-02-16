#!/bin/bash
# lib/kernel.sh — kernel parameter hardening

apply_kernel_parameters() {
    local -A params=(
        [kernel.kptr_restrict]=2
        [kernel.dmesg_restrict]=1
        [kernel.perf_event_paranoid]=3
        [kernel.yama.ptrace_scope]=1
        [net.ipv4.conf.all.accept_redirects]=0
        [net.ipv4.conf.all.accept_source_route]=0
        [net.ipv4.conf.all.rp_filter]=1
        [net.ipv4.tcp_syncookies]=1
    )

    for param in "${!params[@]}"; do
        if ! sysctl -w "${param}=${params[${param}]}" >/dev/null 2>&1; then
            log_warning "Failed to set ${param}=${params[${param}]}"
        fi
    done
}
