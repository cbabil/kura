#!/usr/bin/env bats
# tests/shell/packaging.bats — Kura's own parts as one Debian package per
# image (ADR-025), so a device moves to a new Kura version with apt:
# scripts/packaging/kura-package.sh stages the package from a finished rootfs
# (build time), scripts/common/pkg-hooks.sh is what its postinst runs on the
# device.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    STAGE="${BATS_TEST_TMPDIR}/stage"
    PKG_ROOT="${BATS_TEST_TMPDIR}/device"
    PKG_BRAND=kura
    export PKG_ROOT PKG_BRAND
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/pkg-hooks.sh"
    mkdir -p "${PKG_ROOT}"
}

# fake_rootfs: a finished image, as much of it as the package cares about
fake_rootfs() {
    local f wants="${ROOTFS}/etc/systemd/system"
    for f in usr/bin/kura-config usr/bin/kura-security usr/lib/kura/firstboot.sh usr/lib/kura/security/common.sh \
             usr/lib/kura/kura-desktopd usr/lib/systemd/system/kura-firstboot.service \
             usr/lib/systemd/system/kura-desktopd.service usr/lib/systemd/system/kura-issue.timer \
             usr/lib/systemd/system/docker.service usr/share/dbus-1/system.d/io.kura.Helper.conf \
             usr/lib/sysusers.d/kura-desktop.conf usr/lib/tmpfiles.d/kura-desktop.conf \
             etc/update-motd.d/10-status etc/apt/apt.conf.d/52kura-upgrades etc/apt/apt.conf.d/53kura-docker-upgrades \
             etc/apt/apt.conf.d/20auto-upgrades \
             etc/apt/apt.conf.d/90kura-efi etc/profile.d/kura.sh usr/share/grub/themes/kura/theme.txt \
             usr/share/plymouth/themes/kura/kura.script \
             etc/kura/config.json etc/kura/brand.env etc/kura/security/hardening.json \
             etc/ssh/sshd_config.d/10-kura.conf etc/issue etc/fstab usr/bin/bash; do
        mkdir -p "${ROOTFS}/$(dirname "${f}")"
        echo "${f}" > "${ROOTFS}/${f}"
    done
    echo '{"network_security":{"desktop":true}}' > "${ROOTFS}/etc/kura/security/hardening.json"
    mkdir -p "${wants}/multi-user.target.wants" "${wants}/timers.target.wants"
    ln -s /usr/lib/systemd/system/kura-firstboot.service "${wants}/multi-user.target.wants/"
    ln -s /usr/lib/systemd/system/kura-desktopd.service "${wants}/multi-user.target.wants/"
    ln -s /usr/lib/systemd/system/docker.service "${wants}/multi-user.target.wants/"
    ln -s /usr/lib/systemd/system/kura-issue.timer "${wants}/timers.target.wants/"
}

# ---- build time: staging the package ----

@test "stage: Kura's program files, and nothing a device changes or Debian owns" {
    fake_rootfs
    run stage_kura_package "${ROOTFS}" kura 0.6.0 amd64 "${STAGE}"
    [ "$status" -eq 0 ]
    local f
    for f in usr/bin/kura-config usr/lib/kura/firstboot.sh usr/lib/kura/security/common.sh usr/lib/kura/kura-desktopd \
             usr/lib/systemd/system/kura-firstboot.service usr/lib/systemd/system/kura-issue.timer \
             usr/share/dbus-1/system.d/io.kura.Helper.conf usr/lib/sysusers.d/kura-desktop.conf \
             etc/update-motd.d/10-status etc/apt/apt.conf.d/52kura-upgrades etc/apt/apt.conf.d/53kura-docker-upgrades \
             etc/apt/apt.conf.d/90kura-efi etc/profile.d/kura.sh usr/share/grub/themes/kura/theme.txt \
             usr/share/plymouth/themes/kura/kura.script; do
        [ -f "${STAGE}/${f}" ] || { echo "missing ${f}"; return 1; }
    done
    # the owner's on/off for automatic updates (dpkg-reconfigure) is theirs
    [ ! -e "${STAGE}/etc/apt/apt.conf.d/20auto-upgrades" ]
    for f in etc/kura/config.json etc/kura/brand.env etc/kura/security/hardening.json \
             etc/ssh/sshd_config.d/10-kura.conf etc/issue etc/fstab usr/bin/bash \
             usr/lib/systemd/system/docker.service etc/systemd; do
        [ ! -e "${STAGE}/${f}" ] || { echo "must not ship ${f}"; return 1; }
    done
}

@test "stage: the device's settings ship as defaults, the units to enable as a list" {
    fake_rootfs
    stage_kura_package "${ROOTFS}" kura 0.6.0 amd64 "${STAGE}"
    [ "$(jq -r .network_security.desktop "${STAGE}/usr/lib/kura/defaults/hardening.json")" = true ]
    [ "$(sort "${STAGE}/usr/lib/kura/units.list")" = "$(printf '%s\n' \
        "multi-user.target kura-desktopd.service" "multi-user.target kura-firstboot.service" \
        "timers.target kura-issue.timer")" ]
}

@test "stage: the control file names the package, its version and architecture" {
    fake_rootfs
    stage_kura_package "${ROOTFS}" kura 0.6.0 arm64 "${STAGE}"
    local control="${STAGE}/DEBIAN/control"
    file_has "${control}" "Package: kura"
    file_has "${control}" "Version: 0.6.0"
    file_has "${control}" "Architecture: arm64"
    file_has "${control}" "Maintainer: "
    # what Kura needs from Debian, from the list in the repo, so an upgraded
    # device gets a package a later version added (ADR-030)
    file_has "${control}" "Depends: bash, jq, systemd, avahi-daemon"
    [ -x "${STAGE}/DEBIAN/postinst" ]
    file_has "${STAGE}/DEBIAN/postinst" "/usr/lib/kura/pkg-hooks.sh"
    run grep -c "__BRAND" "${STAGE}/DEBIAN/postinst"
    [ "$output" = "0" ]
}

@test "stage: a version Debian would refuse stops the build" {
    fake_rootfs
    run stage_kura_package "${ROOTFS}" kura "v0.6 beta" amd64 "${STAGE}"
    [ "$status" -ne 0 ]
    # 0.6.0-rc1 would sort after 0.6.0: devices on it would never get the final
    run stage_kura_package "${ROOTFS}" kura "0.6.0-rc1" amd64 "${STAGE}"
    [ "$status" -ne 0 ]
}

# ---- on the device: what the postinst runs ----

units_list() { mkdir -p "${PKG_ROOT}/usr/lib/kura"; printf '%s\n' "$@" > "${PKG_ROOT}/usr/lib/kura/units.list"; }
link() { echo "${PKG_ROOT}/etc/systemd/system/$1.wants/$2"; }

@test "enable_new_units: a fresh install enables every unit of the list" {
    units_list "multi-user.target kura-firstboot.service" "timers.target kura-issue.timer"
    run enable_new_units
    [ "$status" -eq 0 ]
    [ "$(readlink "$(link multi-user.target kura-firstboot.service)")" = "/usr/lib/systemd/system/kura-firstboot.service" ]
    [ -L "$(link timers.target kura-issue.timer)" ]
}

@test "enable_new_units: an upgrade enables only what is new, so a unit the owner turned off stays off" {
    units_list "multi-user.target kura-desktopd.service"
    enable_new_units
    rm "$(link multi-user.target kura-desktopd.service)"          # the owner's "desktop": false
    units_list "multi-user.target kura-desktopd.service" "multi-user.target kura-new.service"
    run enable_new_units
    [ "$status" -eq 0 ]
    [ ! -e "$(link multi-user.target kura-desktopd.service)" ]
    [ -L "$(link multi-user.target kura-new.service)" ]
}

@test "seed_defaults: a missing setting gets its default, an existing one keeps the owner's values and gains new keys" {
    mkdir -p "${PKG_ROOT}/usr/lib/kura/defaults" "${PKG_ROOT}/etc/kura/security"
    echo '{"network_security":{"desktop":true,"new_rule":true},"added":1}' > "${PKG_ROOT}/usr/lib/kura/defaults/hardening.json"
    run seed_defaults
    [ "$status" -eq 0 ]
    [ "$(jq -r .added "${PKG_ROOT}/etc/kura/security/hardening.json")" = 1 ]
    [ "$(file_mode "${PKG_ROOT}/etc/kura/security/hardening.json")" = "600" ]
    echo '{"network_security":{"desktop":false}}' > "${PKG_ROOT}/etc/kura/security/hardening.json"
    run seed_defaults
    [ "$(jq -c .network_security "${PKG_ROOT}/etc/kura/security/hardening.json")" = '{"desktop":false,"new_rule":true}' ]
    [ "$(file_mode "${PKG_ROOT}/etc/kura/security/hardening.json")" = "600" ]
}

@test "seed_defaults: a device file jq cannot read is left alone, and the upgrade goes on" {
    mkdir -p "${PKG_ROOT}/usr/lib/kura/defaults" "${PKG_ROOT}/etc/kura/security"
    echo '{"a":1}' > "${PKG_ROOT}/usr/lib/kura/defaults/hardening.json"
    echo 'not json' > "${PKG_ROOT}/etc/kura/security/hardening.json"
    run seed_defaults
    [ "$status" -eq 0 ]
    [ "$(cat "${PKG_ROOT}/etc/kura/security/hardening.json")" = "not json" ]
}

@test "run_migrations: each runs once, in order; a failing one stops and is tried again next time" {
    local dir="${PKG_ROOT}/usr/lib/kura/migrations" log="${BATS_TEST_TMPDIR}/ran"
    mkdir -p "${dir}"
    printf '#!/bin/sh\necho 001 >> %s\n' "${log}" > "${dir}/001-first.sh"
    printf '#!/bin/sh\necho 002 >> %s\n[ -e %s/ok ]\n' "${log}" "${BATS_TEST_TMPDIR}" > "${dir}/002-second.sh"
    chmod +x "${dir}"/*.sh
    run run_migrations
    [ "$status" -ne 0 ]
    touch "${BATS_TEST_TMPDIR}/ok"
    run run_migrations
    [ "$status" -eq 0 ]
    run run_migrations
    [ "$(tr '\n' ' ' < "${log}")" = "001 002 002 " ]
}

@test "kura_configure: an upgrade (an older version given) restarts what runs Kura's programs" {
    units_list "multi-user.target kura-firstboot.service"
    mkdir -p "${PKG_ROOT}/run/systemd/system"
    systemctl() { echo "systemctl $*" >> "${BATS_TEST_TMPDIR}/systemctl"; }
    run kura_configure 0.5.9
    [ "$status" -eq 0 ]
    file_has "${BATS_TEST_TMPDIR}/systemctl" "systemctl daemon-reload"
    file_has "${BATS_TEST_TMPDIR}/systemctl" "systemctl try-restart kura-helper.service kura-desktopd.service kura-issue.service"
    # avahi takes Kura's settings (its drop-in came with this package)
    file_has "${BATS_TEST_TMPDIR}/systemctl" "systemctl try-restart avahi-daemon.service"
    # the rest (hardening, new units) takes effect at the next start: say so
    [ -e "${PKG_ROOT}/run/reboot-required" ]
}

@test "kura_configure: inside the image build (no running systemd) nothing is restarted" {
    units_list "multi-user.target kura-firstboot.service"
    systemctl() { echo "systemctl $*" >> "${BATS_TEST_TMPDIR}/systemctl"; }
    run kura_configure ""
    [ "$status" -eq 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/systemctl" ]
    [ ! -e "${PKG_ROOT}/run/reboot-required" ]
}

# ---- wiring ----

@test "the build packages the finished rootfs and registers the package in the image" {
    file_has "${REPO_ROOT}/build.sh" "package_kura"
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" 'pkg-hooks.sh'
    # dpkg's own state stays whole, so upgrades work on the device
    run grep -c 'var/cache/debconf' "${REPO_ROOT}/scripts/common/customize-rootfs.sh"
    [ "$output" = "0" ]
}

@test "the version comes from the package's release file, which an upgrade replaces" {
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" '/usr/lib/${BRAND}/release'
    # read after brand.env, whose version is the image's and never changes
    local f
    for f in scripts/common/kura-issue scripts/common/motd/10-status; do
        [ "$(grep -n '\. "${BRAND_ENV}"' "${REPO_ROOT}/${f}" | tail -1 | cut -d: -f1)" -lt \
          "$(grep -n '/release' "${REPO_ROOT}/${f}" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)" ]
    done
}

@test "every image must have the package registered and its hooks" {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/verify-rootfs.sh"
    run rootfs_required_files kura
    output_has "usr/lib/kura/pkg-hooks.sh"
    output_has "usr/lib/kura/release"
    output_has "var/lib/dpkg/info/kura.list"
}
