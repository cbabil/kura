#!/bin/bash
# 001-storage-status — Kura 0.6.0 recorded a disk layout as failed when only
# its last clean-up step did ("unmounting the view of the root"): the volumes
# were mounted and the root's old copies cleared. Where every volume of the
# layout is mounted, the record becomes "applied", and the login screen's
# setup line drops the failure.
#
# Run once by the kura package (pkg-hooks.sh run_migrations). Does nothing
# without that record, so nothing in the image build.

BRAND="${MIGRATION_BRAND:-__BRAND__}"
ROOT="${MIGRATION_ROOT:-}"
STATE="${ROOT}/var/lib/${BRAND}"
REASON="unmounting the view of the root"

[ "$(cat "${STATE}/storage-status" 2>/dev/null)" = "failed: ${REASON}" ] || exit 0

while read -r mount; do
    mountpoint -q "${mount}" || exit 0      # a real failure: left as recorded
done < <(awk -v h="# ${BRAND} disk layout" '$0 == h {f = 1; next} f && $3 == "ext4" {print $2}' "${ROOT}/etc/fstab")

echo "applied" > "${STATE}/storage-status"
[ -f "${STATE}/setup-status" ] || exit 0
# the setup line without that entry: "applied" when nothing else was skipped
line=$(sed -e "s/, disk layout failed (${REASON}[^)]*)//" -e "s/disk layout failed (${REASON}[^)]*), //" \
           -e "s/^partly applied: disk layout failed (${REASON}[^)]*)\$/applied/" "${STATE}/setup-status")
printf '%s\n' "${line}" > "${STATE}/setup-status"
