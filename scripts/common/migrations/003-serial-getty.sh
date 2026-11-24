#!/bin/bash
# 003-serial-getty — Kura up to 0.7.0 forced a login prompt onto the first
# serial port of every PC. A PC without that port has the device's name and
# nothing behind it, so the prompt failed and was restarted every ten
# seconds, for ever. The link Kura made is removed: systemd starts a prompt
# by itself on a serial console the kernel has, and the package now makes
# that prompt check that its port answers (serial-getty@.service.d). A link
# the owner made themselves is left alone, and so is a mask.
#
# Run once by the kura package (pkg-hooks.sh run_migrations), which has
# systemd read its units again afterwards: the prompt's next restart meets
# the new check, and a port that does not answer ends the loop there. In
# the image build there is no such link any more.

ROOT="${MIGRATION_ROOT:-}"
LINK="${ROOT}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

[ -L "${LINK}" ] || exit 0
[ "$(readlink "${LINK}")" = "/usr/lib/systemd/system/serial-getty@.service" ] || exit 0
rm -f "${LINK}"
