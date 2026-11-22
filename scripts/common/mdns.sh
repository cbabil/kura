#!/bin/bash
# scripts/common/mdns.sh — kura.local (ADR-030): avahi with Kura's settings.
#
# The settings are a file of the kura package, read through a drop-in of
# avahi-daemon.service, so a device that upgrades with apt runs the same
# settings as a new image. /etc/avahi/avahi-daemon.conf stays Debian's: it is
# avahi-daemon's own configuration file, and a second package must not
# replace it.
#
# Source this file; it defines functions only.

# install_mdns <rootfs> <brand>
install_mdns() {
    local rootfs="$1" brand="$2" here dropin
    here="$(dirname "${BASH_SOURCE[0]}")"
    dropin="${rootfs}/usr/lib/systemd/system/avahi-daemon.service.d"
    install -d "${rootfs}/usr/lib/${brand}" "${dropin}"
    install -m 0644 "${here}/avahi-daemon.conf" "${rootfs}/usr/lib/${brand}/avahi-daemon.conf"
    cat > "${dropin}/10-${brand}.conf" <<DROPIN
# ${brand}: avahi reads Kura's settings (ADR-030)
[Service]
ExecStart=
ExecStart=/usr/sbin/avahi-daemon -s -f /usr/lib/${brand}/avahi-daemon.conf
DROPIN
    chmod 0644 "${dropin}/10-${brand}.conf"
}
