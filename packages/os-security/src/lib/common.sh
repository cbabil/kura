#!/bin/bash
# lib/common.sh — shared helpers for os-security
# Provides logging and validation functions.

# ---- Logging ----
log_info()    { echo "INFO:  $*"; }
log_warning() { echo "WARNING: $*" >&2; }
log_error()   { echo "ERROR: $*" >&2; }

# ---- Validation ----

# Validate a profile/rule name (AppArmor, Seccomp, etc.)
# Allowed: start with alnum, then alnum/dot/underscore/hyphen.
validate_name() {
    local name="$1"
    if [[ -z "${name}" ]] || ! [[ "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        log_error "Invalid name: '${name}'"
        return 1
    fi
}

# Validate a domain name for firewall whitelist.
# Rejects empty, >253 chars, unresolved __*__ placeholders.
validate_domain() {
    local domain="$1"
    if [[ -z "${domain}" ]] || [[ ${#domain} -gt 253 ]]; then
        return 1
    fi
    # Reject unresolved build-time placeholders
    if [[ "${domain}" == __*__ ]]; then
        return 1
    fi
    if ! [[ "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
}

# Write content to a file with explicit mode (0644 by default).
# Reads stdin, writes atomically via temp file + rename.
write_file() {
    local dest="$1" mode="${2:-0644}"
    local dir tmp
    dir=$(dirname "${dest}")
    tmp=$(mktemp "${dir}/.tmp.XXXXXX")
    cat > "${tmp}"
    chmod "${mode}" "${tmp}"
    mv "${tmp}" "${dest}"
}
