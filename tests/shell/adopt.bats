#!/usr/bin/env bats
# tests/shell/adopt.bats — kura-adopt.sh (ADR-025): run once on a device
# installed before Kura had packages (0.5.2), it adds Kura's repository and
# installs the kura package over the files already there. Made by
# scripts/release/make-adopt.sh; apt and dpkg are stubbed.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    ADOPT="${BATS_TEST_TMPDIR}/kura-adopt.sh"
    "${REPO_ROOT}/scripts/release/make-adopt.sh" kura cbabil/kura > "${ADOPT}"
    ADOPT_ROOT="${BATS_TEST_TMPDIR}/device"
    ADOPT_SOURCED=1
    CALLS="${BATS_TEST_TMPDIR}/calls"
    export ADOPT_ROOT ADOPT_SOURCED CALLS
    mkdir -p "${ADOPT_ROOT}/usr/lib/systemd/system" "${ADOPT_ROOT}/var/lib/kura"
    # shellcheck disable=SC1090
    source "${ADOPT}"
    set +euo pipefail
}

stub_tools() {
    id() { echo 0; }
    dpkg-query() { return 1; }                       # kura not installed yet
    apt-get() {
        log_call "apt-get $*"
        [ "$1" != download ] || touch "kura_0.6.0_amd64.deb"
    }
    dpkg-deb() { echo fsys; }
    tar() { printf '%s\n' "multi-user.target kura-desktopd.service" "multi-user.target kura-new.service"; }
    dpkg() { log_call "dpkg $*"; }
}

@test "make-adopt: a complete script, with the repository's files inside" {
    bash -n "${ADOPT}"
    run grep -c "__[A-Z_]*__" "${ADOPT}"
    [ "$output" = "0" ]
    file_has "${ADOPT}" "sudo bash"
}

@test "adopt_files: the key, the source and the pin, as every new image has them" {
    run adopt_files
    [ "$status" -eq 0 ]
    grep -q "BEGIN PGP PUBLIC KEY BLOCK" "${ADOPT_ROOT}/usr/share/keyrings/kura-archive.asc"
    file_has "${ADOPT_ROOT}/etc/apt/sources.list.d/kura.sources" \
        "URIs: https://github.com/cbabil/kura/releases/latest/download/"
    file_has "${ADOPT_ROOT}/etc/apt/preferences.d/kura-archive" "Pin-Priority: -1"
}

@test "seed_units: units the device already has keep their on/off state; new ones get enabled" {
    touch "${ADOPT_ROOT}/usr/lib/systemd/system/kura-desktopd.service"
    printf '%s\n' "multi-user.target kura-desktopd.service" "multi-user.target kura-new.service" | seed_units
    [ "$(cat "${ADOPT_ROOT}/var/lib/kura/units-enabled")" = "multi-user.target kura-desktopd.service" ]
}

@test "adopt: refreshes Kura's lists only, seeds the units, installs the checked package" {
    stub_tools
    touch "${ADOPT_ROOT}/usr/lib/systemd/system/kura-desktopd.service"
    run adopt
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "apt-get update -o Dir::Etc::sourcelist=sources.list.d/kura.sources -o Dir::Etc::sourceparts=-"
    file_has "${CALLS}" "apt-get download kura"
    grep -q "^dpkg -i .*kura_0.6.0_amd64.deb" "${CALLS}"
    [ "$(cat "${ADOPT_ROOT}/var/lib/kura/units-enabled")" = "multi-user.target kura-desktopd.service" ]
    # the seeding comes before the install, whose postinst reads it
    output_has "sudo apt full-upgrade"
}

@test "adopt: a device that already has the package is left to apt" {
    stub_tools
    dpkg-query() { echo "install ok installed"; }
    run adopt
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
    output_has "sudo apt full-upgrade"
}

@test "adopt: needs root, and stops when the download fails" {
    stub_tools
    id() { echo 1000; }
    run adopt
    [ "$status" -ne 0 ]
    id() { echo 0; }
    apt-get() { [ "$1" != download ]; }
    run adopt
    [ "$status" -ne 0 ]
    [ ! -e "${CALLS}" ]
}

@test "the release publishes kura-adopt.sh" {
    file_has "${REPO_ROOT}/.github/workflows/release.yml" "make-adopt.sh"
    file_has "${REPO_ROOT}/.github/workflows/release.yml" "kura-adopt.sh"
}

@test "CI upgrades the released image in place with the package just built" {
    local wf="${REPO_ROOT}/.github/workflows/images.yml"
    file_has "${wf}" "tests/boot/upgrade-test.sh"
    [ -x "${REPO_ROOT}/tests/boot/upgrade-test.sh" ]
    # the settings an upgrade must leave alone are compared before and after
    file_has "${REPO_ROOT}/tests/boot/upgrade-test.sh" "owner_state_kept"
}
