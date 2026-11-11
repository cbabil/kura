#!/usr/bin/env bats
# tests/shell/auto-updates.bats — security updates install themselves:
# Debian's security and updates suites are in every image's sources, the
# build installs their latest packages, unattended-upgrades runs daily, and
# the clock is kept in sync (TLS and APT need it).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/auto-updates.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}/etc/apt/sources.list.d"
    printf 'ID=debian\nVERSION_CODENAME=trixie\n' > "${ROOTFS}/etc/os-release"
}

# ---- add_debian_updates ----

@test "add_debian_updates: deb822 sources gain trixie-updates and a security stanza" {
    cat > "${ROOTFS}/etc/apt/sources.list.d/debian.sources" <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    add_debian_updates "${ROOTFS}"
    local f="${ROOTFS}/etc/apt/sources.list.d/debian.sources"
    grep -qxF "Suites: trixie trixie-updates" "${f}"
    grep -qxF "URIs: https://security.debian.org/debian-security" "${f}"
    grep -qxF "Suites: trixie-security" "${f}"
    [ "$(grep -c '^Components: main non-free-firmware$' "${f}")" -eq 2 ]
    [ "$(grep -c '^Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg$' "${f}")" -eq 2 ]
}

@test "add_debian_updates: one-line sources gain the same suites" {
    echo "deb https://deb.debian.org/debian trixie main non-free-firmware" > "${ROOTFS}/etc/apt/sources.list"
    add_debian_updates "${ROOTFS}"
    local f="${ROOTFS}/etc/apt/sources.list"
    grep -qxF "deb https://deb.debian.org/debian trixie-updates main non-free-firmware" "${f}"
    grep -qxF "deb https://security.debian.org/debian-security trixie-security main non-free-firmware" "${f}"
}

@test "add_debian_updates: running twice adds nothing more" {
    echo "deb https://deb.debian.org/debian trixie main" > "${ROOTFS}/etc/apt/sources.list"
    add_debian_updates "${ROOTFS}"
    add_debian_updates "${ROOTFS}"
    [ "$(wc -l < "${ROOTFS}/etc/apt/sources.list")" -eq 3 ]
}

@test "both targets add Debian's update suites; the build upgrades before installing" {
    grep -q "add_debian_updates" "${REPO_ROOT}/scripts/rpi5/configure-repos.sh"
    grep -q "add_debian_updates" "${REPO_ROOT}/scripts/x86_64/configure-repos.sh"
    grep -q 'chroot "${ROOTFS}" apt-get upgrade' "${REPO_ROOT}/build.sh"
}

# ---- install_auto_updates ----

@test "install_auto_updates: daily package lists and unattended upgrades" {
    install_auto_updates "${ROOTFS}" kura
    local f="${ROOTFS}/etc/apt/apt.conf.d/20auto-upgrades"
    grep -qxF 'APT::Periodic::Update-Package-Lists "1";' "${f}"
    grep -qxF 'APT::Periodic::Unattended-Upgrade "1";' "${f}"
}

@test "install_auto_updates: Docker's repo too, and a reboot at 04:30 when needed" {
    install_auto_updates "${ROOTFS}" kura
    file_has "${ROOTFS}/etc/apt/apt.conf.d/53kura-docker-upgrades" \
        '"origin=Docker,label=Docker CE,archive=${distro_codename}";'
    local f="${ROOTFS}/etc/apt/apt.conf.d/52kura-upgrades"
    file_has "${f}" 'Unattended-Upgrade::Automatic-Reboot "true";'
    file_has "${f}" 'Unattended-Upgrade::Automatic-Reboot-Time "04:30";'
    file_has "${f}" 'Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";'
    file_has "${f}" 'Acquire::Languages "none";'
}

@test "install_auto_updates: the APT timers and the clock sync are enabled" {
    install_auto_updates "${ROOTFS}" kura
    [ -L "${ROOTFS}/etc/systemd/system/timers.target.wants/apt-daily.timer" ]
    [ -L "${ROOTFS}/etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer" ]
    [ -L "${ROOTFS}/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service" ]
}

@test "add_update_origin: a target's own repo is upgraded too" {
    add_update_origin "${ROOTFS}" kura raspi 'origin=Raspberry Pi Foundation,codename=${distro_codename}'
    file_has "${ROOTFS}/etc/apt/apt.conf.d/53kura-raspi-upgrades" \
        '"origin=Raspberry Pi Foundation,codename=${distro_codename}";'
}

@test "every image installs unattended-upgrades and a clock sync; both targets call the setup" {
    grep -qx "unattended-upgrades" "${REPO_ROOT}/config/packages-common.list"
    grep -qx "systemd-timesyncd" "${REPO_ROOT}/config/packages-common.list"
    grep -q 'install_auto_updates "${ROOTFS}"' "${REPO_ROOT}/scripts/common/customize-rootfs.sh"
    grep -q "add_update_origin.*Raspberry Pi Foundation" "${REPO_ROOT}/scripts/rpi5/customize-rootfs.sh"
}
