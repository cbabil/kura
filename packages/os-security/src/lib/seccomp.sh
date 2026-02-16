#!/bin/bash
# lib/seccomp.sh — Seccomp profile deployment

apply_seccomp_profiles() {
    local config_file="$1"
    local count
    count=$(jq '.seccomp_profiles | length' "${config_file}" 2>/dev/null)

    if [[ -z "${count}" ]] || [[ "${count}" -eq 0 ]]; then
        log_info "No Seccomp profiles configured, skipping"
        return 0
    fi

    local seccomp_dir="/etc/__BRAND__/security/seccomp"
    mkdir -p "${seccomp_dir}"

    local i name rules
    for ((i = 0; i < count; i++)); do
        name=$(jq -r ".seccomp_profiles[${i}].name" "${config_file}")
        rules=$(jq -c ".seccomp_profiles[${i}].rules" "${config_file}")

        if ! validate_name "${name}"; then
            log_warning "Skipping invalid Seccomp profile name: '${name}'"
            continue
        fi

        printf '%s' "${rules}" | write_file "${seccomp_dir}/${name}"
    done
}
