#!/bin/bash
# scripts/common/auto-updates.sh
# Security updates that install themselves. unattended-upgrades runs daily
# (apt-daily-upgrade.timer). Debian's own 50unattended-upgrades covers
# Debian and Debian-Security; Kura adds Docker's repo and, per target, its
# own (the Pi's kernel and firmware). A device reboots at 04:30 only when an
# update needs it (a new kernel). systemd-timesyncd keeps the clock right,
# which TLS and APT's signature dates need (a Pi has no battery clock).
#
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/apt-components.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/systemd-units.sh"

# install_auto_updates <rootfs> <brand>
install_auto_updates() {
    local rootfs="$1" brand="$2" conf="$1/etc/apt/apt.conf.d" units=/usr/lib/systemd/system
    install -d "${conf}"
    cat > "${conf}/20auto-upgrades" <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF
    cat > "${conf}/52${brand}-upgrades" <<'CONF'
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
// No translated package descriptions: less to download and write each day
Acquire::Languages "none";
CONF
    # ${distro_codename} is unattended-upgrades' own variable, not the shell's
    # shellcheck disable=SC2016
    add_update_origin "${rootfs}" "${brand}" docker 'origin=Docker,label=Docker CE,archive=${distro_codename}'
    enable_unit "${rootfs}" timers.target "${units}/apt-daily.timer"
    enable_unit "${rootfs}" timers.target "${units}/apt-daily-upgrade.timer"
    enable_unit "${rootfs}" sysinit.target "${units}/systemd-timesyncd.service"
}

# add_update_origin <rootfs> <brand> <name> <origins-pattern>: one more repo
# whose updates install themselves
add_update_origin() {
    install -d "$1/etc/apt/apt.conf.d"
    printf 'Unattended-Upgrade::Origins-Pattern {\n    "%s";\n};\n' "$4" \
        > "$1/etc/apt/apt.conf.d/53$2-$3-upgrades"
}
