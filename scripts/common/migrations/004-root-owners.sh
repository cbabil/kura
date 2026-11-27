#!/bin/bash
# 004-root-owners — images up to 0.7.1 copied the overlays into the image
# with rsync -a, which kept the owner of the build's checkout (ID 1001 on
# CI) on every overlay file and on each folder above them, / and /etc
# included. The first account a device's owner made got ID 1001, and with
# it / and /etc: root's power, and sshd refuses keys under a folder it does
# not trust. Each of those paths, and each folder above it, goes back to
# root. The build now copies them as root (rsync --chown=0:0), and the image
# check fails on any path whose owner has no account.
#
# The list holds every path any Kura overlay installed (the test checks that
# it covers the current ones). Paths a device does not have are skipped.
#
# Run once by the kura package (pkg-hooks.sh run_migrations). In the image
# build they are root's already, so nothing changes.

ROOT="${MIGRATION_ROOT:-}"
PATHS=(
    /etc/kura/config.json
    /etc/plymouth/plymouthd.conf
    /usr/share/grub/themes/kura/select_c.png
    /usr/share/grub/themes/kura/select_e.png
    /usr/share/grub/themes/kura/select_n.png
    /usr/share/grub/themes/kura/select_ne.png
    /usr/share/grub/themes/kura/select_nw.png
    /usr/share/grub/themes/kura/select_s.png
    /usr/share/grub/themes/kura/select_se.png
    /usr/share/grub/themes/kura/select_sw.png
    /usr/share/grub/themes/kura/select_w.png
    /usr/share/grub/themes/kura/theme.txt
    /usr/share/plymouth/themes/kura/dot.png
    /usr/share/plymouth/themes/kura/kura.plymouth
    /usr/share/plymouth/themes/kura/kura.script
    /usr/share/plymouth/themes/kura/logo.png
    /etc/kura/supervisor-config.json
    /etc/issue
    /etc/motd
)

# root_path <path>: <path> and each folder above it, up to /, root's
root_path() {
    local p="$1"
    while :; do
        if [ -e "${ROOT}${p}" ] || [ -L "${ROOT}${p}" ]; then
            chown -h 0:0 "${ROOT}${p}" || return 1
        fi
        [ "${p}" = / ] && return 0
        p=$(dirname "${p}")
    done
}

for path in "${PATHS[@]}"; do
    root_path "${path}" || exit 1
done
