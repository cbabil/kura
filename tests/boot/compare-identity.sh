#!/bin/bash
# tests/boot/compare-identity.sh <identity-a> <identity-b>
#
# Compares two identity.txt reports written by iso-boot-test.sh from two boots
# of the same image. Each device must generate its own identity, so every
# value (SSH host key, machine-id, JWT secret hash) must be present in both
# and differ. Exits 1 if any value is missing or shared.

set -euo pipefail

A="${1:?Usage: $0 <identity-a> <identity-b>}"
B="${2:?Usage: $0 <identity-a> <identity-b>}"

for f in "${A}" "${B}"; do
    if [ ! -f "${f}" ]; then
        echo "FAIL identity report ${f} not found"
        exit 1
    fi
done

status=0
for key in ssh_host_key machine_id jwt_secret; do
    a=$(awk -v k="${key}" '$1 == k {print $2}' "${A}")
    b=$(awk -v k="${key}" '$1 == k {print $2}' "${B}")
    if [ -z "${a}" ] || [ -z "${b}" ]; then
        echo "FAIL ${key}: missing from a report"
        status=1
    elif [ "${a}" = "${b}" ]; then
        echo "FAIL ${key}: both boots share ${a}"
        status=1
    else
        echo "PASS ${key} differs"
    fi
done
exit "${status}"
