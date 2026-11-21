#!/bin/bash
# 002-console-font — Kura up to 0.6.0 set the console font to Terminus in
# console-setup's "Uni3" set, which has no half blocks: the storehouse
# character on the login screen is drawn with them. A device still on that
# set moves to "Vietnamese" (the widest Latin set, with the half blocks), and
# the font is applied now. A set the owner chose is left alone.
#
# Run once by the kura package (pkg-hooks.sh run_migrations). In the image
# build the set is already the new one, so nothing happens.

ROOT="${MIGRATION_ROOT:-}"
CONF="${ROOT}/etc/default/console-setup"

grep -qx 'CODESET="Uni3"' "${CONF}" 2>/dev/null || exit 0

out=$(sed 's/^CODESET="Uni3"$/CODESET="Vietnamese"/' "${CONF}") && printf '%s\n' "${out}" > "${CONF}" || exit 1
# console-setup's copies of the old font, made at the first boot
rm -f "${ROOT}"/etc/console-setup/cached_*
# on a running device, now; otherwise at the next boot
[ ! -d "${ROOT}/run/systemd/system" ] || setupcon --save --force 2>/dev/null || true
