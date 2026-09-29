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
source "$(dirname "$0")/docker-repo.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
# Validate BRAND (must be lowercase alphanumeric with hyphens, no shell metacharacters)
if ! [[ "${BRAND}" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: Invalid OS_BRAND '${BRAND}' (must be lowercase alphanumeric with hyphens)" >&2
    exit 1
fi
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
COLOR="${OS_COLOR:-${DEFAULT_COLOR}}"
HOSTNAME="${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}"
export ROOT_PASSWD="${OS_ROOT_PASSWD:-${DEFAULT_ROOT_PASSWD}}"
LOGIN_USER="${OS_USER:-admin}"
export LOGIN_USER_PASSWD="${OS_USER_PASSWD:-admin}"
VERSION="${OS_VERSION:-0.0.1}"
DHCP_IFACE="${OS_DHCP_INTERFACE:-eth0}"
API_ENDPOINT="${OS_API_ENDPOINT:-${DEFAULT_API_ENDPOINT}}"
WS_ENDPOINT="${OS_WS_ENDPOINT:-${DEFAULT_WS_ENDPOINT}}"
REGISTRY="${OS_REGISTRY:-${DEFAULT_REGISTRY}}"
WS_HEARTBEAT_INTERVAL="${OS_WS_HEARTBEAT_INTERVAL:-${DEFAULT_WS_HEARTBEAT_INTERVAL}}"
WS_HEARTBEAT_TIMEOUT="${OS_WS_HEARTBEAT_TIMEOUT:-${DEFAULT_WS_HEARTBEAT_TIMEOUT}}"
WS_RECONNECT_BASE="${OS_WS_RECONNECT_BASE:-${DEFAULT_WS_RECONNECT_BASE}}"
WS_RECONNECT_MAX="${OS_WS_RECONNECT_MAX:-${DEFAULT_WS_RECONNECT_MAX}}"

echo "Customizing rootfs at ${ROOTFS}..."

# ---- Directory structure ----
install -d -m 0755 -o 999 -g 999 "${ROOTFS}/var/lib/${BRAND}"
install -d -m 0755 -o 999 -g 999 "${ROOTFS}/var/lib/${BRAND}/volumes"
install -d -m 0755 -o 999 -g 999 "${ROOTFS}/var/lib/${BRAND}-supervisor"
install -d -m 0755 -o 999 -g 999 "${ROOTFS}/var/log/${BRAND}"
install -d -m 0750 -g 999 "${ROOTFS}/etc/${BRAND}/certs"
install -d -m 0755 "${ROOTFS}/mnt/data"

# ---- System user for supervisor (runs unprivileged) ----
if ! grep -q "^${BRAND}:" "${ROOTFS}/etc/passwd" 2>/dev/null; then
    echo "${BRAND}:x:999:999:${OS_NAME} Supervisor:/opt/${BRAND}-supervisor:/usr/sbin/nologin" \
        >> "${ROOTFS}/etc/passwd"
    echo "${BRAND}:x:999:" >> "${ROOTFS}/etc/group"
    echo "${BRAND}:!:19000:0:99999:7:::" >> "${ROOTFS}/etc/shadow"
fi
# Add brand user to docker group (docker group is created later by Docker install)
if grep -q "^docker:" "${ROOTFS}/etc/group" 2>/dev/null &&
   ! grep -q "^docker:.*:${BRAND}\(,\|$\)" "${ROOTFS}/etc/group"; then
    # Append to docker group members (handles both empty and non-empty member lists)
    sed -i "s/^\(docker:[^:]*:[^:]*:.*\)$/\1,${BRAND}/; s/:,/:/" "${ROOTFS}/etc/group"
fi

# ---- Hostname ----
echo "${HOSTNAME}" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}
::1		localhost ip6-localhost ip6-loopback
EOF

# ---- Permissions ----
# /etc/${BRAND} readable by brand group (supervisor needs config access)
chmod 750 "${ROOTFS}/etc/${BRAND}"
chgrp 999 "${ROOTFS}/etc/${BRAND}"

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

# Suppress "terminal is not fully functional" from less/systemctl.
# Debian trixie ncurses 6.x wide-format terminfo can be unreadable by less;
# the -d flag tells less to silently ignore missing terminal capabilities.
export SYSTEMD_LESS=FRSXMKd
export LESS='-FRSXMKd'

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
enable_docker_units "${ROOTFS}"

# multi-user.target (service names use ${BRAND} prefix)
for svc in ${BRAND}-supervisor ${BRAND}-config; do
    ln -sf "/usr/lib/systemd/system/${svc}.service" \
        "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${svc}.service"
done

# sysinit.target (security runs early)
install -d "${ROOTFS}/etc/systemd/system/sysinit.target.wants"
ln -sf "/usr/lib/systemd/system/${BRAND}-security.service" \
    "${ROOTFS}/etc/systemd/system/sysinit.target.wants/${BRAND}-security.service"

# /etc/environment — read by PAM (pam_env) for ALL sessions before any shell.
# -d flag suppresses "terminal is not fully functional" from less (ncurses 6.x
# wide-format terminfo on Debian trixie is unreadable by less).
# Append only if not already present (idempotent)
if ! grep -q 'SYSTEMD_LESS=' "${ROOTFS}/etc/environment" 2>/dev/null; then
    cat >> "${ROOTFS}/etc/environment" <<'ENVEOF'
SYSTEMD_LESS=FRSXMKd
LESS=-FRSXMKd
ENVEOF
fi

# Ensure /etc/resolv.conf is a regular writable file (not a stale symlink).
# NM with dns=default writes nameservers directly here at runtime.
rm -f "${ROOTFS}/etc/resolv.conf"
touch "${ROOTFS}/etc/resolv.conf"

# NetworkManager wait-online (required for network-online.target to actually wait)
install -d "${ROOTFS}/etc/systemd/system/network-online.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
    "${ROOTFS}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"

# Increase NM wait-online timeout (default 30s is too short for live-boot VMs)
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
BRAND_API_ENDPOINT="${API_ENDPOINT}"
BRAND_WS_ENDPOINT="${WS_ENDPOINT}"
BRAND_REGISTRY="${REGISTRY}"
BRAND_WS_HEARTBEAT_INTERVAL="${WS_HEARTBEAT_INTERVAL}"
BRAND_WS_HEARTBEAT_TIMEOUT="${WS_HEARTBEAT_TIMEOUT}"
BRAND_WS_RECONNECT_BASE="${WS_RECONNECT_BASE}"
BRAND_WS_RECONNECT_MAX="${WS_RECONNECT_MAX}"
BRANDEOF
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
    sed -i "s|\"path\": \"[^\"]*\"|\"path\": \"/var/log/${BRAND}\"|" \
        "${ROOTFS}/etc/${BRAND}/config.json"
    chown 999:999 "${ROOTFS}/etc/${BRAND}/config.json"
    chmod 600 "${ROOTFS}/etc/${BRAND}/config.json"
fi

# ---- ANSI color definitions (from brand color) ----
ESC=$'\033'
_r=$((16#${COLOR:1:2})); _g=$((16#${COLOR:3:2})); _b=$((16#${COLOR:5:2}))
B="${ESC}[38;2;${_r};${_g};${_b}m"
G="${B}"
R="${ESC}[0m"

# ---- Generate colored /etc/issue (pre-login banner) ----
# agetty passes raw ANSI bytes through; \r \m \l are agetty escapes
cat > "${ROOTFS}/etc/issue" <<ISSUEEOF

${B}  ██   ██ ██    ██ ██████   █████
  ██  ██  ██    ██ ██   ██ ██   ██
  █████   ██    ██ ██████  ███████
  ██  ██  ██    ██ ██   ██ ██   ██
  ██   ██  ██████  ██   ██ ██   ██${R}

${G}  ${OS_ISSUE:-Welcome to ${OS_NAME}}${R}

ISSUEEOF

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

# ---- Set passwords ----
# Uses chpasswd inside chroot (called by build.sh after mounting /proc etc.)
# build.sh will run: chroot ${ROOTFS} sh -c "echo 'root:...\n${LOGIN_USER}:...' | chpasswd"

# ---- Locale (C + en_US) ----
if [ -f "${ROOTFS}/etc/locale.gen" ]; then
    sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' "${ROOTFS}/etc/locale.gen"
fi

# ---- Sudoers: allow brand user to reboot/shutdown (supervisor runs unprivileged) ----
install -d -m 0750 "${ROOTFS}/etc/sudoers.d"
cat > "${ROOTFS}/etc/sudoers.d/${BRAND}" <<SUDOEOF
${BRAND} ALL=(root) NOPASSWD: /usr/bin/systemctl reboot, /usr/bin/systemctl poweroff
SUDOEOF
chmod 440 "${ROOTFS}/etc/sudoers.d/${BRAND}"

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
# Skip /usr/local/bin/bun — it embeds resources and breaks if stripped.
find "${ROOTFS}/usr/lib" "${ROOTFS}/usr/bin" "${ROOTFS}/usr/sbin" \
    "${ROOTFS}/lib" "${ROOTFS}/bin" "${ROOTFS}/sbin" \
    -type f \( -name '*.so*' -o -executable \) \
    ! -name 'bun' \
    -exec strip --strip-unneeded {} + 2>/dev/null || true

# Supervisor node_modules: remove non-runtime files
for NM_DIR in "${ROOTFS}"/opt/*-supervisor/node_modules; do
    [ -d "${NM_DIR}" ] || continue
    find "${NM_DIR}" \( \
        -name 'README*' -o -name 'LICENSE*' -o -name 'CHANGELOG*' \
        -o -name 'HISTORY*' -o -name '*.md' -o -name '*.ts' \
        -o -name '*.map' -o -name '*.flow' -o -name '.eslint*' \
        -o -name '.prettier*' -o -name 'Makefile' \
        -o -name '.package-lock.json' -o -name '.npmignore' \
        -o -name '.travis.yml' -o -name '.github' \
    \) -exec rm -rf {} + 2>/dev/null || true
    # Remove test/example directories inside deps
    find "${NM_DIR}" -type d \( \
        -name 'test' -o -name 'tests' -o -name '__tests__' \
        -o -name 'example' -o -name 'examples' -o -name 'benchmark' \
    \) -exec rm -rf {} + 2>/dev/null || true
done

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
