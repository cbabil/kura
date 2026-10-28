#!/bin/bash
# scripts/common/customize-rootfs.sh
# Shared rootfs customization (runs outside chroot, operates on rootfs directory).
# Common rootfs customizations applied during build
#
# Usage: customize-rootfs.sh <rootfs-dir>
# Requires: OS_* env vars exported by build.sh

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/brand-defaults.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/systemd-units.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/install-firstboot.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
# Validate BRAND (must be lowercase alphanumeric with hyphens, no shell metacharacters)
if ! [[ "${BRAND}" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: Invalid OS_BRAND '${BRAND}' (must be lowercase alphanumeric with hyphens)" >&2
    exit 1
fi
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
COLOR="${OS_COLOR:-${DEFAULT_COLOR}}"
# The README banner's tagline, on the login screen and the SSH welcome
TAGLINE="${OS_ISSUE:-${DEFAULT_TAGLINE}}"
HOSTNAME="${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}"
LOGIN_USER="${OS_USER:-${DEFAULT_USER}}"
VERSION="${OS_VERSION:-0.0.1}"
DHCP_IFACE="${OS_DHCP_INTERFACE:-eth0}"

echo "Customizing rootfs at ${ROOTFS}..."

# ---- Directory structure ----
install -d -m 0755 "${ROOTFS}/var/lib/${BRAND}"

# ---- Hostname ----
echo "${HOSTNAME}" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}
::1		localhost ip6-localhost ip6-loopback
EOF

# ---- Shell environment ----
install -d "${ROOTFS}/etc/profile.d"
# Derive RGB from hex color for truecolor escape
_cr=$((16#${COLOR:1:2})); _cg=$((16#${COLOR:3:2})); _cb=$((16#${COLOR:5:2}))
cat > "${ROOTFS}/etc/profile.d/${BRAND}.sh" <<PROFEOF
export OS_CONFIG=/etc/${BRAND}/config.json

# Fall back to xterm-256color for terminals without local terminfo
case "\$TERM" in
    xterm-256color|xterm|linux|vt*|screen*|tmux*|dumb) ;;
    *) export TERM=xterm-256color ;;
esac

# Brand color (${COLOR}) applied to prompt and cursor
if [ "\$TERM" = "linux" ]; then
    PROMPT_COMMAND='printf "\033[1;35m"'
else
    PROMPT_COMMAND='printf "\033[38;2;${_cr};${_cg};${_cb}m"'
fi
PS1='\u@\h:\w > '
# Blinking block cursor + matching brand color
printf '\033[1 q' 2>/dev/null
printf '\033]12;${COLOR}\007' 2>/dev/null
PROFEOF

# ---- Silence kernel console after early boot ----
# GRUB sets loglevel=7 so kernel + systemd boot messages are visible.
# systemd-sysctl.service runs at sysinit.target and applies this config,
# dropping the console log level to 1 (emergency only) before any late
# modules (bridge, xfrm, etc.) produce noise on the login screen.
install -d "${ROOTFS}/etc/sysctl.d"
cat > "${ROOTFS}/etc/sysctl.d/99-console-loglevel.conf" <<'SYSEOF'
kernel.printk = 1 4 1 7
SYSEOF

# ---- Enable systemd services ----
# Docker is baked into every image (packages-common.list)
enable_unit "${ROOTFS}" multi-user.target /usr/lib/systemd/system/docker.service
enable_unit "${ROOTFS}" multi-user.target /usr/lib/systemd/system/containerd.service

# First boot: SSH host keys, the imager's setup file, root partition growth,
# hostname from user-data
install_firstboot "${ROOTFS}" "${BRAND}" "${OS_NAME}" "$(dirname "$0")"
install_login_screen "${ROOTFS}" "${BRAND}" "${OS_NAME}" "$(dirname "$0")"

# ---- Console font: Terminus 16x32, the login screen's design size ----
# (120x33 on a 1080p screen; console-setup applies it at boot). Uni3 has the
# blocks, box drawing, bullet and triangle the screen draws (ADR-019).
install -d "${ROOTFS}/etc/default"
cat > "${ROOTFS}/etc/default/console-setup" <<'CONSOLEEOF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Uni3"
FONTFACE="Terminus"
FONTSIZE="16x32"
VIDEOMODE=
CONSOLEEOF
# console-setup reuses the font setup it cached when it was installed (the
# default font) and would ignore this file; without the cache, the first boot
# runs setupcon with it and caches the Terminus setup
rm -f "${ROOTFS}"/etc/console-setup/cached_*

enable_unit "${ROOTFS}" multi-user.target "/usr/lib/systemd/system/${BRAND}-config.service"

# sysinit.target (security runs early)
enable_unit "${ROOTFS}" sysinit.target "/usr/lib/systemd/system/${BRAND}-security.service"


# Ensure /etc/resolv.conf is a regular writable file (not a stale symlink).
# NM with dns=default writes nameservers directly here at runtime.
rm -f "${ROOTFS}/etc/resolv.conf"
touch "${ROOTFS}/etc/resolv.conf"

# NetworkManager wait-online (required for network-online.target to actually wait)
install -d "${ROOTFS}/etc/systemd/system/network-online.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
    "${ROOTFS}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"

# Increase NM wait-online timeout (default 30s is too short for slow VMs)
install -d "${ROOTFS}/etc/systemd/system/NetworkManager-wait-online.service.d"
cat > "${ROOTFS}/etc/systemd/system/NetworkManager-wait-online.service.d/timeout.conf" <<'NMEOF'
[Service]
ExecStart=
ExecStart=/usr/bin/nm-online -s -q --timeout=120
NMEOF

# ---- Generate brand.env (runtime brand discovery) ----
# Always at /etc/kura/brand.env -- this is the bootstrap path that runtime
# code uses to discover the brand. The path itself never changes.
install -d "${ROOTFS}/etc/kura"
cat > "${ROOTFS}/etc/kura/brand.env" <<BRANDEOF
BRAND_NAME="${OS_NAME}"
BRAND_PREFIX="${BRAND}"
BRAND_COLOR="${COLOR}"
BRAND_VERSION="${VERSION}"
BRANDEOF
# Quoted for the shells that source brand.env, whatever OS_ISSUE holds
printf 'BRAND_TAGLINE=%q\n' "${TAGLINE}" >> "${ROOTFS}/etc/kura/brand.env"
chmod 644 "${ROOTFS}/etc/kura/brand.env"

# ---- Patch config.json with env values ----
if [ -f "${ROOTFS}/etc/${BRAND}/config.json" ]; then
    sed -i "s/\"name\": \"[^\"]*\"/\"name\": \"${OS_NAME}\"/" \
        "${ROOTFS}/etc/${BRAND}/config.json"
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"${VERSION}\"/" \
        "${ROOTFS}/etc/${BRAND}/config.json"
    sed -i "s/\"hostname\": \"[^\"]*\"/\"hostname\": \"${HOSTNAME}\"/" \
        "${ROOTFS}/etc/${BRAND}/config.json"
    sed -i "s/\"interface\": \"[^\"]*\"/\"interface\": \"${DHCP_IFACE}\"/" \
        "${ROOTFS}/etc/${BRAND}/config.json"
    chmod 600 "${ROOTFS}/etc/${BRAND}/config.json"
fi

# ---- /etc/issue: the console login screen (ADR-018, ADR-019) ----
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/issue.sh"
LOGIN_USER="" kura_issue "${TAGLINE}" "${COLOR#\#}" > "${ROOTFS}/etc/issue"

# ---- Install dynamic MOTD scripts ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Remove any default Debian MOTD scripts (e.g. 10-uname)
rm -rf "${ROOTFS}/etc/update-motd.d"/*

install -d -m 0755 "${ROOTFS}/etc/update-motd.d"
for script in 05-ssh-banner 10-banner 40-status 80-commands; do
    install -m 0755 "${SCRIPT_DIR}/motd/${script}" "${ROOTFS}/etc/update-motd.d/${script}"
done

# Empty static motd (dynamic scripts handle everything)
: > "${ROOTFS}/etc/motd"

# ---- Login user (SSH with password) ----
# Create login user with home directory; password set via chroot later by build.sh
if ! grep -q "^${LOGIN_USER}:" "${ROOTFS}/etc/passwd" 2>/dev/null; then
    echo "${LOGIN_USER}:x:1000:1000:${LOGIN_USER}:/home/${LOGIN_USER}:/bin/bash" \
        >> "${ROOTFS}/etc/passwd"
    echo "${LOGIN_USER}:x:1000:" >> "${ROOTFS}/etc/group"
    echo "${LOGIN_USER}:!:19000:0:99999:7:::" >> "${ROOTFS}/etc/shadow"
    install -d -m 0700 -o 1000 -g 1000 "${ROOTFS}/home/${LOGIN_USER}"
fi
# Add login user to sudo group
if grep -q "^sudo:" "${ROOTFS}/etc/group" 2>/dev/null &&
   ! grep -q "^sudo:.*${LOGIN_USER}" "${ROOTFS}/etc/group"; then
    sed -i "s/^\(sudo:[^:]*:[^:]*:.*\)$/\1,${LOGIN_USER}/; s/:,/:/" "${ROOTFS}/etc/group"
fi

# ---- SSH: root key-only, login user password allowed ----
install -d "${ROOTFS}/etc/ssh/sshd_config.d"
cat > "${ROOTFS}/etc/ssh/sshd_config.d/10-${BRAND}.conf" <<SSHEOF
PermitRootLogin prohibit-password
PasswordAuthentication no

Match User ${LOGIN_USER}
    PasswordAuthentication yes
SSHEOF

# Passwords: set_passwords (scripts/common/passwords.sh), run by build.sh.

# ---- Locale (C + en_US) ----
if [ -f "${ROOTFS}/etc/locale.gen" ]; then
    sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' "${ROOTFS}/etc/locale.gen"
fi

# ---- Journald: limit persistent log storage ----
JOURNAL_MAX="${OS_JOURNAL_MAX_SIZE:-100M}"
JOURNAL_MAX_FILE="${OS_JOURNAL_MAX_FILE_SEC:-1week}"
install -d "${ROOTFS}/etc/systemd/journald.conf.d"
cat > "${ROOTFS}/etc/systemd/journald.conf.d/10-size-limit.conf" <<JRNLEOF
[Journal]
SystemMaxUse=${JOURNAL_MAX}
MaxFileSec=${JOURNAL_MAX_FILE}
JRNLEOF

# ---- Aggressive cleanup to reduce image size ----
echo "Stripping rootfs to reduce image size..."

# Apt/dpkg metadata (immutable OS — not needed at runtime)
rm -rf "${ROOTFS}/var/cache/apt/archives"/*.deb
rm -rf "${ROOTFS}/var/lib/apt/lists"/*
rm -rf "${ROOTFS}/var/cache/debconf"/*
rm -rf "${ROOTFS}/var/lib/dpkg/info"/*.md5sums
rm -rf "${ROOTFS}/usr/share/bug"
rm -rf "${ROOTFS}/usr/share/lintian"

# Strip debug symbols from ELF binaries and shared libraries.
find "${ROOTFS}/usr/lib" "${ROOTFS}/usr/bin" "${ROOTFS}/usr/sbin" \
    "${ROOTFS}/lib" "${ROOTFS}/bin" "${ROOTFS}/sbin" \
    -type f \( -name '*.so*' -o -executable \) \
    -exec strip --strip-unneeded {} + 2>/dev/null || true

# GnuPG: remove data files (only needed during package install)
rm -rf "${ROOTFS}/usr/share/gnupg"

# Shell completions (not used in embedded OS)
rm -rf "${ROOTFS}/usr/share/bash-completion"
rm -rf "${ROOTFS}/usr/share/zsh"

# Miscellaneous docs/data not caught by per-target stripping
rm -rf "${ROOTFS}/usr/share/pixmaps"
rm -rf "${ROOTFS}/usr/share/applications"
rm -rf "${ROOTFS}/usr/share/icons"

# Logs (will be recreated at boot)
find "${ROOTFS}/var/log" -type f -name '*.log' -delete 2>/dev/null || true
rm -rf "${ROOTFS}/var/log/apt"

# Temp files
rm -rf "${ROOTFS}/tmp"/*
rm -rf "${ROOTFS}/var/tmp"/*

echo "Common rootfs customization complete."
