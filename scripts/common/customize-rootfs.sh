#!/bin/bash
# scripts/common/customize-rootfs.sh
# Shared rootfs customization (runs outside chroot, operates on rootfs directory).
# Adapted from buildroot-external post-build.sh
#
# Usage: customize-rootfs.sh <rootfs-dir>
# Requires: OS_* env vars exported by build.sh

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
HOSTNAME="${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}"
export ROOT_PASSWD="${OS_ROOT_PASSWD:-${DEFAULT_ROOT_PASSWD}}"
VERSION="${OS_VERSION:-2.0}"
DHCP_IFACE="${OS_DHCP_INTERFACE:-eth0}"
API_ENDPOINT="${OS_API_ENDPOINT:-${DEFAULT_API_ENDPOINT}}"
REGISTRY="${OS_REGISTRY:-${DEFAULT_REGISTRY}}"

echo "Customizing rootfs at ${ROOTFS}..."

# ---- Directory structure ----
install -d -m 0755 "${ROOTFS}/var/lib/${BRAND}"
install -d -m 0755 "${ROOTFS}/var/lib/${BRAND}/volumes"
install -d -m 0755 "${ROOTFS}/var/lib/${BRAND}-supervisor"
install -d -m 0755 "${ROOTFS}/var/log/${BRAND}"
install -d -m 0700 "${ROOTFS}/etc/${BRAND}/certs"
install -d -m 0755 "${ROOTFS}/mnt/data"

# ---- Hostname ----
echo "${HOSTNAME}" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}
::1		localhost ip6-localhost ip6-loopback
EOF

# ---- Permissions ----
chmod 700 "${ROOTFS}/etc/${BRAND}"
chmod 755 "${ROOTFS}/var/lib/${BRAND}"
chmod 755 "${ROOTFS}/var/log/${BRAND}"

# ---- Python environment ----
install -d "${ROOTFS}/etc/profile.d"
cat > "${ROOTFS}/etc/profile.d/${BRAND}.sh" <<'PROFEOF'
export PYTHONPATH=/usr/lib/__BRAND__
export OS_CONFIG=/etc/__BRAND__/config.json

# IBM green phosphor terminal style
# Re-apply green before every prompt (survives commands that reset colors)
PROMPT_COMMAND='printf "\033[0;32m"'
PS1='\u@\h:\w > '
# Blinking block cursor + green cursor color (xterm-compatible terminals)
printf '\033[1 q' 2>/dev/null
printf '\033]12;#33ff00\007' 2>/dev/null
PROFEOF
sed -i "s|__BRAND__|${BRAND}|g" "${ROOTFS}/etc/profile.d/${BRAND}.sh"

# ---- Enable systemd services ----
# multi-user.target (service names use ${BRAND} prefix)
for svc in ${BRAND}-supervisor ${BRAND}-config; do
    install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
    ln -sf "/usr/lib/systemd/system/${svc}.service" \
        "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${svc}.service"
done

# sysinit.target (security runs early)
install -d "${ROOTFS}/etc/systemd/system/sysinit.target.wants"
ln -sf "/usr/lib/systemd/system/${BRAND}-security.service" \
    "${ROOTFS}/etc/systemd/system/sysinit.target.wants/${BRAND}-security.service"

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
# Always at /etc/falken/brand.env -- this is the bootstrap path that runtime
# code uses to discover the brand. The path itself never changes.
install -d "${ROOTFS}/etc/falken"
cat > "${ROOTFS}/etc/falken/brand.env" <<BRANDEOF
BRAND_NAME="${OS_NAME}"
BRAND_PREFIX="${BRAND}"
BRAND_VERSION="${VERSION}"
BRAND_API_ENDPOINT="${API_ENDPOINT}"
BRAND_REGISTRY="${REGISTRY}"
BRANDEOF
chmod 644 "${ROOTFS}/etc/falken/brand.env"

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
fi

# ---- ANSI color definitions (IBM green phosphor) ----
ESC=$'\033'
B="${ESC}[1;32m"    # bright green
G="${ESC}[0;32m"    # normal green
R="${ESC}[0m"       # reset

# ---- Generate colored /etc/issue (pre-login banner) ----
# agetty passes raw ANSI bytes through; \r \m \l are agetty escapes
cat > "${ROOTFS}/etc/issue" <<ISSUEEOF

${B}  ███████  █████  ██      ██   ██ ███████ ███    ██
  ██      ██   ██ ██      ██  ██  ██      ████   ██
  █████   ███████ ██      █████   █████   ██ ██  ██
  ██      ██   ██ ██      ██  ██  ██      ██  ██ ██
  ██      ██   ██ ███████ ██   ██ ███████ ██   ████${R}

${G}  "Greetings, Professor Falken. Shall we play a game?"${R}

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

# ---- Install easter egg commands (WarGames, 1983) ----
for egg in "${SCRIPT_DIR}/easter-eggs"/*; do
    install -m 0755 "${egg}" "${ROOTFS}/usr/local/bin/$(basename "${egg}")"
done

# ---- SSH: allow root login with password ----
install -d "${ROOTFS}/etc/ssh/sshd_config.d"
cat > "${ROOTFS}/etc/ssh/sshd_config.d/10-${BRAND}.conf" <<SSHEOF
PermitRootLogin yes
PrintLastLog no
SSHEOF

# ---- Set root password ----
# Uses chpasswd inside chroot (called by build.sh after mounting /proc etc.)
# build.sh will run: chroot ${ROOTFS} sh -c "echo 'root:${ROOT_PASSWD}' | chpasswd"

# ---- Locale (C + en_US) ----
if [ -f "${ROOTFS}/etc/locale.gen" ]; then
    sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' "${ROOTFS}/etc/locale.gen"
fi

# ---- Aggressive cleanup to reduce image size ----
echo "Stripping rootfs to reduce image size..."

# Apt/dpkg metadata (immutable OS — not needed at runtime)
rm -rf "${ROOTFS}/var/cache/apt/archives"/*.deb
rm -rf "${ROOTFS}/var/lib/apt/lists"/*
rm -rf "${ROOTFS}/var/cache/debconf"/*
rm -rf "${ROOTFS}/var/lib/dpkg/info"/*.md5sums
rm -rf "${ROOTFS}/usr/share/bug"
rm -rf "${ROOTFS}/usr/share/lintian"

# Python bytecode caches
find "${ROOTFS}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find "${ROOTFS}" -name '*.pyc' -delete 2>/dev/null || true

# Python packaging metadata (not needed at runtime)
find "${ROOTFS}" -type d -name '*.dist-info' -exec rm -rf {} + 2>/dev/null || true
find "${ROOTFS}" -type d -name '*.egg-info' -exec rm -rf {} + 2>/dev/null || true

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
