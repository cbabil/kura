#!/bin/bash
# scripts/common/firstboot-storage-check.sh
# The "storage" key of __BRAND__-setup.json: its validation, and the outcome
# the disk layout (firstboot-storage.sh) leaves for first boot's setup line
# and for resize_root. Sourced by both; uses SETUP_ROOT and SETUP_BRAND.
# Defines functions only.
#
#   "storage": {"rootGiB": 16, "tmpGiB": 1, "swapGiB": 4,
#               "volumes": [{"mount": "/var/log", "sizeGiB": 4},
#                           {"mount": "/var/lib/docker"}]}
#
# Every key is optional. A volume without sizeGiB takes the rest of the disk.
# A volume can be any plain folder (/var and /var/lib included) except the
# system's own (STORAGE_SYSTEM) and the brand's state; /tmp is either a RAM
# disk sized by tmpGiB or a volume, not both.

# shellcheck disable=SC2016  # jq programs are single-quoted on purpose

# folders that stay on the root, with everything under them (/var/run and
# /var/lock are links into /run)
STORAGE_SYSTEM='["/boot","/etc","/usr","/bin","/sbin","/lib","/lib32","/lib64","/dev","/proc","/sys","/run","/root","/var/run","/var/lock"]'

# jq definitions shared with storage_plan: a folder's volume name
STORAGE_JQ_DEFS='def lv_name: ltrimstr("/") | gsub("/"; "-");'

# validate_storage <file>: the first problem with the storage key, or nothing
# (also when there is no storage key)
validate_storage() {
    jq -r --argjson system "${STORAGE_SYSTEM}" --arg state "/var/lib/${SETUP_BRAND}" "${STORAGE_JQ_DEFS}"'
        def whole: type == "number" and . == floor and . >= 1 and . <= 4096;
        def plain: type == "string" and length <= 64
            and test("^(/[A-Za-z0-9._-]+)+$")
            and (split("/")[1:] | all(. != "." and . != ".."));
        def under($dir): . == $dir or startswith($dir + "/");
        def stays_on_root: any(($system + [$state])[] as $d | under($d); .) or startswith("/tmp/");
        # names LVM refuses or keeps for itself
        def lvm_refuses: (split("/") | any(startswith("-")))
            or (lv_name | . == "snapshot" or . == "pvmove"
                or test("_(cdata|cmeta|corig|mimage|mlog|pmspare|rimage|rmeta|tdata|tmeta|vorigin|vdata)"));
        .storage as $s
        | if $s == null then empty
          elif ($s | type) != "object" then "storage is not an object"
          elif $s.rootGiB != null and ($s.rootGiB | whole | not) then
              "the root size is not a whole number of GiB"
          elif $s.rootGiB != null and $s.rootGiB < 4 then "the root needs at least 4 GiB"
          elif $s.tmpGiB != null and ($s.tmpGiB | whole | not) then
              "the /tmp size is not a whole number of GiB"
          elif $s.swapGiB != null and ($s.swapGiB | whole | not) then
              "the swap size is not a whole number of GiB"
          elif $s.swapGiB != null and $s.rootGiB == null then "swap needs a root size"
          elif $s.volumes != null and ($s.volumes | type) != "array" then "volumes is not a list"
          elif $s.volumes != null and $s.rootGiB == null then "volumes need a root size"
          elif $s.rootGiB != null and $s.swapGiB == null and ($s.volumes // [] | length) == 0 then
              "a root size needs at least one volume"
          elif $s.volumes == null then empty
          else first(
              ($s.volumes[]
                | if type != "object" then "a volume is not an object"
                  elif (.mount | plain | not) then "a volume'"'"'s folder is not a plain absolute path"
                  elif (.mount | stays_on_root or lvm_refuses) then "\(.mount) cannot be a separate volume"
                  elif .sizeGiB != null and (.sizeGiB | whole | not) then
                      "the \(.mount) size is not a whole number of GiB"
                  else empty end),
              ($s.volumes | group_by(.mount)[] | select(length > 1) | "\(.[0].mount) is listed twice"),
              ($s.volumes | map(.mount) | group_by(lv_name)[] | select(length > 1)
                | "\(.[0]) and \(.[1]) would share a volume name"),
              (if $s.swapGiB != null and any($s.volumes[]; .mount | lv_name == "swap")
               then "/swap would share the swap volume'"'"'s name" else empty end),
              (if $s.tmpGiB != null and any($s.volumes[]; .mount == "/tmp")
               then "/tmp is either in RAM or a volume" else empty end),
              (if [$s.volumes[] | select(.sizeGiB == null)] | length > 1
               then "only one volume can take the rest of the disk" else empty end)
          ) // empty end' "$1"
}

# storage_applied: the disk layout was built (and sized the root); state_file
# is firstboot-disk.sh's
storage_applied() { [ "$(cat "$(state_file storage-status)" 2>/dev/null)" = "applied" ]; }
