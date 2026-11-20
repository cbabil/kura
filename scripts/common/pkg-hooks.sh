#!/bin/bash
# scripts/common/pkg-hooks.sh — run by the kura package's postinst (ADR-025)
# when the package is installed or upgraded: installed as
# /usr/lib/<brand>/pkg-hooks.sh by customize-rootfs.sh, which fills in the
# brand. The package replaces Kura's programs; these functions do the rest,
# and never touch what the owner set.
#
# PKG_ROOT is a scratch root in the tests. Defines functions only.

PKG_BRAND="${PKG_BRAND:-__BRAND__}"
PKG_ROOT="${PKG_ROOT:-}"
PKG_LIB="${PKG_ROOT}/usr/lib/${PKG_BRAND}"
PKG_STATE="${PKG_ROOT}/var/lib/${PKG_BRAND}"

# enable_new_units: enable the units of units.list ("<target> <unit>") that
# this device has not been given before. A unit the owner turned off since
# (the Desktop, SSH) stays off; one that is new in this version comes on.
enable_new_units() {
    local target unit wants seen="${PKG_STATE}/units-enabled"
    mkdir -p "${PKG_STATE}"
    touch "${seen}"
    while read -r target unit; do
        [ -n "${unit}" ] || continue
        grep -qxF "${target} ${unit}" "${seen}" && continue
        wants="${PKG_ROOT}/etc/systemd/system/${target}.wants"
        mkdir -p "${wants}" &&
        ln -sf "/usr/lib/systemd/system/${unit}" "${wants}/${unit}" &&
        echo "${target} ${unit}" >> "${seen}" || return 1
    done < "${PKG_LIB}/units.list"
}

# seed_defaults: hardening.json from the package's default when the device
# has none; otherwise the device's file gains the default's new keys and
# keeps every value it has
seed_defaults() {
    local default="${PKG_LIB}/defaults/hardening.json" file="${PKG_ROOT}/etc/${PKG_BRAND}/security/hardening.json" merged
    [ -f "${default}" ] || return 0
    mkdir -p "$(dirname "${file}")"
    if [ -f "${file}" ]; then
        # a file jq cannot read is the owner's to fix; the upgrade goes on
        merged=$(jq -s '.[0] * .[1]' "${default}" "${file}" 2>/dev/null) || {
            echo "WARNING: ${PKG_BRAND}: ${file} is not valid JSON; left as it is" >&2
            return 0
        }
    else
        merged=$(cat "${default}")
    fi
    (umask 077 && printf '%s\n' "${merged}" > "${file}.new") && mv "${file}.new" "${file}"
}

# run_migrations: each script of migrations/ once, in name order; the first
# that fails stops the run and is tried again at the next upgrade
run_migrations() {
    local script name done_list="${PKG_STATE}/migrations"
    mkdir -p "${PKG_STATE}"
    touch "${done_list}"
    for script in "${PKG_LIB}"/migrations/*.sh; do
        [ -f "${script}" ] || continue
        name=$(basename "${script}")
        grep -qxF "${name}" "${done_list}" && continue
        "${script}" || { echo "ERROR: ${PKG_BRAND}: migration ${name} failed" >&2; return 1; }
        echo "${name}" >> "${done_list}"
    done
}

# kura_configure <version-before>: the postinst's work. <version-before> is
# empty on a first install (the image build is one).
kura_configure() {
    enable_new_units && seed_defaults && run_migrations || return 1
    # Nothing to restart inside the image build
    [ -d "${PKG_ROOT}/run/systemd/system" ] || return 0
    systemctl daemon-reload || true
    [ -n "${1:-}" ] || return 0
    # An upgrade: Kura's running programs take the new version now; what
    # runs at boot (hardening, new units) does at the next start, which the
    # login screen and the message after login then ask for
    systemd-sysusers 2>/dev/null || true
    systemd-tmpfiles --create 2>/dev/null || true
    systemctl try-restart "${PKG_BRAND}-helper.service" "${PKG_BRAND}-desktopd.service" \
        "${PKG_BRAND}-issue.service" || true
    touch "${PKG_ROOT}/run/reboot-required"
}
