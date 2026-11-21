#!/usr/bin/env bats
# tests/shell/migrations.bats — the kura package's migrations
# (scripts/common/migrations/, ADR-025): each runs once on a device when the
# package is installed or upgraded, and must do nothing in the image build.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    MIG="${REPO_ROOT}/scripts/common/migrations"
    ROOT="${BATS_TEST_TMPDIR}/root"
    mkdir -p "${ROOT}/var/lib/kura" "${ROOT}/etc" "${BATS_TEST_TMPDIR}/bin"
    printf '%s\n' "/dev/sda2 / ext4 defaults 0 1" "# kura disk layout" \
        "/dev/kura/var-log /var/log ext4 noexec,nosuid,nodev 0 2" "/dev/kura/opt /opt ext4 nosuid,nodev 0 2" \
        > "${ROOT}/etc/fstab"
    # mountpoint: the folders named in MOUNTED are mounted
    printf '#!/bin/sh\ncase " $MOUNTED " in *" $2 "*) exit 0;; esac\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/mountpoint"
    chmod +x "${BATS_TEST_TMPDIR}/bin/mountpoint"
    export MIGRATION_ROOT="${ROOT}" MIGRATION_BRAND=kura PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    FALSE_FAILURE="failed: unmounting the view of the root"
}

status() { cat "${ROOT}/var/lib/kura/$1"; }

@test "001: a layout that 0.6.0 wrongly recorded as failed is recorded as applied" {
    echo "${FALSE_FAILURE}" > "${ROOT}/var/lib/kura/storage-status"
    echo "partly applied: disk layout failed (unmounting the view of the root; journalctl -u kura-storage)" \
        > "${ROOT}/var/lib/kura/setup-status"
    MOUNTED="/var/log /opt" run "${MIG}/001-storage-status.sh"
    [ "$status" -eq 0 ]
    [ "$(status storage-status)" = "applied" ]
    [ "$(status setup-status)" = "applied" ]
}

@test "001: other skipped settings stay on the setup line" {
    echo "${FALSE_FAILURE}" > "${ROOT}/var/lib/kura/storage-status"
    echo "partly applied: Wi-Fi skipped (invalid SSID), disk layout failed (unmounting the view of the root; journalctl -u kura-storage)" \
        > "${ROOT}/var/lib/kura/setup-status"
    MOUNTED="/var/log /opt" run "${MIG}/001-storage-status.sh"
    [ "$(status setup-status)" = "partly applied: Wi-Fi skipped (invalid SSID)" ]
}

@test "001: a volume that really is not mounted keeps the failure" {
    echo "${FALSE_FAILURE}" > "${ROOT}/var/lib/kura/storage-status"
    MOUNTED="/var/log" run "${MIG}/001-storage-status.sh"
    [ "$status" -eq 0 ]
    [ "$(status storage-status)" = "${FALSE_FAILURE}" ]
}

@test "001: any other status, or none (the image build), is left alone" {
    run "${MIG}/001-storage-status.sh"
    [ "$status" -eq 0 ]
    [ ! -e "${ROOT}/var/lib/kura/storage-status" ]
    echo "failed: mounting /opt" > "${ROOT}/var/lib/kura/storage-status"
    MOUNTED="/var/log /opt" run "${MIG}/001-storage-status.sh"
    [ "$(status storage-status)" = "failed: mounting /opt" ]
}

@test "the image carries the migrations, in the package, executable" {
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" "migrations"
    local m
    for m in "${MIG}"/*.sh; do [ -x "${m}" ]; done
}

@test "002: a device on the old font set moves to the one with the half blocks, and applies it" {
    mkdir -p "${ROOT}/etc/default" "${ROOT}/etc/console-setup" "${ROOT}/run/systemd/system"
    printf 'CHARMAP="UTF-8"\nCODESET="Uni3"\nFONTFACE="Terminus"\nFONTSIZE="16x32"\n' > "${ROOT}/etc/default/console-setup"
    touch "${ROOT}/etc/console-setup/cached_setup_font.sh" "${ROOT}/etc/console-setup/cached_Uni3-Terminus32x16.psf.gz"
    printf '#!/bin/sh\necho "setupcon $*" >> "%s/calls"\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/setupcon"
    chmod +x "${BATS_TEST_TMPDIR}/bin/setupcon"
    run "${MIG}/002-console-font.sh"
    [ "$status" -eq 0 ]
    file_has "${ROOT}/etc/default/console-setup" 'CODESET="Vietnamese"'
    file_has "${ROOT}/etc/default/console-setup" 'FONTSIZE="16x32"'
    [ -z "$(ls "${ROOT}/etc/console-setup")" ]
    file_has "${BATS_TEST_TMPDIR}/calls" "setupcon --save --force"
}

@test "002: a font set the owner chose, or no console setup (the image build), is left alone" {
    run "${MIG}/002-console-font.sh"
    [ "$status" -eq 0 ]
    mkdir -p "${ROOT}/etc/default"
    printf 'CODESET="Lat15"\n' > "${ROOT}/etc/default/console-setup"
    run "${MIG}/002-console-font.sh"
    [ "$(cat "${ROOT}/etc/default/console-setup")" = 'CODESET="Lat15"' ]
    [ ! -e "${BATS_TEST_TMPDIR}/calls" ]
}
