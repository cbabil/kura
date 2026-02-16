#!/bin/bash
# lib/filesystem.sh — filesystem hardening (mount options + fstab)

apply_filesystem_hardening() {
    local -A mount_opts=(
        [/tmp]="noexec,nosuid,nodev"
        [/var/tmp]="noexec,nosuid,nodev"
        [/dev/shm]="noexec,nosuid,nodev"
        [/home]="nodev"
    )

    for mp in "${!mount_opts[@]}"; do
        if ! mount -o "remount,${mount_opts[${mp}]}" "${mp}" 2>/dev/null; then
            log_warning "Failed to remount ${mp}"
        fi
    done

    _update_fstab
}

_update_fstab() {
    local fstab="/etc/fstab"
    [[ -f "${fstab}" ]] || return 0

    local -A mount_opts=(
        [/tmp]="noexec,nosuid,nodev"
        [/var/tmp]="noexec,nosuid,nodev"
        [/dev/shm]="noexec,nosuid,nodev"
        [/home]="nodev"
    )

    local tmp_file
    tmp_file=$(mktemp /etc/.fstab.tmp.XXXXXX)

    while IFS= read -r line; do
        # Preserve comments and blank lines
        if [[ -z "${line}" ]] || [[ "${line}" == \#* ]]; then
            printf '%s\n' "${line}"
            continue
        fi

        # shellcheck disable=SC2162
        read -a parts <<< "${line}"
        if [[ ${#parts[@]} -lt 4 ]]; then
            printf '%s\n' "${line}"
            continue
        fi

        local mp="${parts[1]}"
        if [[ -n "${mount_opts[${mp}]+x}" ]]; then
            parts[3]="${mount_opts[${mp}]}"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${parts[0]}" "${parts[1]}" "${parts[2]}" \
                "${parts[3]}" "${parts[4]:-0}" "${parts[5]:-0}"
        else
            printf '%s\n' "${line}"
        fi
    done < "${fstab}" > "${tmp_file}"

    chmod 0644 "${tmp_file}"
    mv "${tmp_file}" "${fstab}"
}
