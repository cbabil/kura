#!/bin/bash
# lib/apparmor.sh — AppArmor profile deployment

apply_apparmor_profiles() {
    local config_file="$1"
    local count
    count=$(jq '.apparmor_profiles | length' "${config_file}" 2>/dev/null)

    if [[ -z "${count}" ]] || [[ "${count}" -eq 0 ]]; then
        log_info "No AppArmor profiles configured, skipping"
        return 0
    fi

    local profiles_dir="/etc/apparmor.d/__BRAND__"
    mkdir -p "${profiles_dir}"

    local i name content
    for ((i = 0; i < count; i++)); do
        name=$(jq -r ".apparmor_profiles[${i}].name" "${config_file}")
        content=$(jq -r ".apparmor_profiles[${i}].content" "${config_file}")

        if ! validate_name "${name}"; then
            log_warning "Skipping invalid AppArmor profile name: '${name}'"
            continue
        fi

        printf '%s' "${content}" | write_file "${profiles_dir}/${name}"
    done

    if ! apparmor_parser -r -T "${profiles_dir}" 2>/dev/null; then
        log_warning "Failed to reload AppArmor profiles"
    fi
}
