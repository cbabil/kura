#!/bin/bash
# scripts/common/firstboot-storage-check.sh
# The "storage" key of __BRAND__-setup.json: its validation, and the outcome
# the disk layout (firstboot-storage.sh) leaves for first boot's setup line
# and for resize_root. Sourced by both; uses SETUP_ROOT and SETUP_BRAND.
# Defines functions only.
#
#   "storage": {"rootGiB": 16, "tmpGiB": 1,
#               "volumes": [{"mount": "/var/log", "sizeGiB": 4},
#                           {"mount": "/var/lib/docker"}]}
#
# Every key is optional. A volume without sizeGiB takes the rest of the disk.

# shellcheck disable=SC2016  # jq programs are single-quoted on purpose

STORAGE_MOUNTS='["/home","/srv","/opt","/var/log","/var/tmp","/var/lib/docker"]'

# validate_storage <file>: the first problem with the storage key, or nothing
# (also when there is no storage key)
validate_storage() {
    jq -r --argjson allowed "${STORAGE_MOUNTS}" '
        def whole: type == "number" and . == floor and . >= 1 and . <= 4096;
        .storage as $s
        | if $s == null then empty
          elif ($s | type) != "object" then "storage is not an object"
          elif $s.rootGiB != null and ($s.rootGiB | whole | not) then
              "the root size is not a whole number of GiB"
          elif $s.rootGiB != null and $s.rootGiB < 4 then "the root needs at least 4 GiB"
          elif $s.tmpGiB != null and ($s.tmpGiB | whole | not) then
              "the /tmp size is not a whole number of GiB"
          elif $s.volumes == null and $s.rootGiB != null then "a root size needs at least one volume"
          elif $s.volumes == null then empty
          elif ($s.volumes | type) != "array" then "volumes is not a list"
          elif $s.rootGiB == null then "volumes need a root size"
          elif ($s.volumes | length) == 0 then "a root size needs at least one volume"
          else first(
              ($s.volumes[]
                | if type != "object" then "a volume is not an object"
                  elif .mount == "/var" then "/var cannot be a separate volume"
                  elif (.mount | IN($allowed[]) | not) then "a volume'"'"'s mount point is not allowed"
                  elif .sizeGiB != null and (.sizeGiB | whole | not) then
                      "the \(.mount) size is not a whole number of GiB"
                  else empty end),
              ($s.volumes | group_by(.mount)[] | select(length > 1) | "\(.[0].mount) is listed twice"),
              (if [$s.volumes[] | select(.sizeGiB == null)] | length > 1
               then "only one volume can take the rest of the disk" else empty end)
          ) // empty end' "$1"
}

# storage_applied: the disk layout was built (and sized the root); state_file
# is firstboot-disk.sh's
storage_applied() { [ "$(cat "$(state_file storage-status)" 2>/dev/null)" = "applied" ]; }
