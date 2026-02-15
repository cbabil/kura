#!/bin/bash
# RPi5 post-build script
# Runs after rootfs is created but before image is generated

set -e

TARGET_DIR=$1

# Single source of truth for default brand values
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/common/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
API_ENDPOINT="${OS_API_ENDPOINT:-${DEFAULT_API_ENDPOINT}}"
REGISTRY="${OS_REGISTRY:-${DEFAULT_REGISTRY}}"
API_DOMAIN="${API_ENDPOINT#*://}"
BASE_DOMAIN="${API_DOMAIN#*.}"
UPDATES_DOMAIN="updates.${BASE_DOMAIN}"

echo "${OS_NAME}: Running post-build configuration..."

# Create required directories
mkdir -p ${TARGET_DIR}/var/lib/${BRAND}
mkdir -p ${TARGET_DIR}/var/log/${BRAND}
mkdir -p ${TARGET_DIR}/etc/${BRAND}/certs
mkdir -p ${TARGET_DIR}/mnt/data

# Enable OS services
if [ -d ${TARGET_DIR}/usr/lib/systemd/system ]; then
    mkdir -p ${TARGET_DIR}/etc/systemd/system/multi-user.target.wants

    # Enable services (service names use ${BRAND} prefix)
    for service in ${BRAND}-supervisor ${BRAND}-config; do
        if [ -f ${TARGET_DIR}/usr/lib/systemd/system/${service}.service ]; then
            ln -sf /usr/lib/systemd/system/${service}.service \
                ${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/${service}.service
            echo "Enabled ${service}.service"
        fi
    done

    # Enable security service at boot
    mkdir -p ${TARGET_DIR}/etc/systemd/system/sysinit.target.wants
    if [ -f ${TARGET_DIR}/usr/lib/systemd/system/${BRAND}-security.service ]; then
        ln -sf /usr/lib/systemd/system/${BRAND}-security.service \
            ${TARGET_DIR}/etc/systemd/system/sysinit.target.wants/${BRAND}-security.service
        echo "Enabled ${BRAND}-security.service"
    fi
fi

# Set hostname
echo "${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}" > ${TARGET_DIR}/etc/hostname

# Configure hosts file
cat > ${TARGET_DIR}/etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       ${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}
::1             localhost ip6-localhost ip6-loopback
EOF

# Set permissions
chmod 700 ${TARGET_DIR}/etc/${BRAND}
chmod 755 ${TARGET_DIR}/var/lib/${BRAND}
chmod 755 ${TARGET_DIR}/var/log/${BRAND}

# Create environment configuration
mkdir -p ${TARGET_DIR}/etc/profile.d
cat > ${TARGET_DIR}/etc/profile.d/${BRAND}.sh << PROFEOF
export OS_CONFIG=/etc/${BRAND}/config.json
PROFEOF

# Patch config.json with env values
CONF="${TARGET_DIR}/etc/${BRAND}/config.json"
if [ -f "${CONF}" ]; then
    sed -i "s|\"name\": \"[^\"]*\"|\"name\": \"${OS_NAME}\"|" "${CONF}"
    sed -i "s|\"version\": \"[^\"]*\"|\"version\": \"${OS_VERSION:-1.0}\"|" "${CONF}"
    sed -i "s|\"hostname\": \"[^\"]*\"|\"hostname\": \"${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}\"|" "${CONF}"
    sed -i "s|\"interface\": \"[^\"]*\"|\"interface\": \"${OS_DHCP_INTERFACE:-eth0}\"|" "${CONF}"
    sed -i "s|\"path\": \"[^\"]*\"|\"path\": \"/var/log/${BRAND}\"|" "${CONF}"
fi

# Patch Python sources: replace __BRAND__ placeholder with actual brand
for pyfile in "${TARGET_DIR}/usr/lib/${BRAND}/security_hardening.py" \
              "${TARGET_DIR}/usr/lib/${BRAND}/network_manager.py"; do
    if [ -f "${pyfile}" ]; then
        sed -i "s|__BRAND__|${BRAND}|g" "${pyfile}"
    fi
done

# Patch hardening.json: replace domain placeholders with actual values
if [ -f "${TARGET_DIR}/etc/${BRAND}/security/hardening.json" ]; then
    sed -i "s|__REGISTRY__|${REGISTRY}|g; \
            s|__API_DOMAIN__|${API_DOMAIN}|g; \
            s|__UPDATES_DOMAIN__|${UPDATES_DOMAIN}|g" \
        "${TARGET_DIR}/etc/${BRAND}/security/hardening.json"
fi

# Patch service file placeholders
for svc_file in "${BRAND}-supervisor" "${BRAND}-config" "${BRAND}-security"; do
    if [ -f "${TARGET_DIR}/usr/lib/systemd/system/${svc_file}.service" ]; then
        sed -i "s|__BRAND__|${BRAND}|g; s|__BRAND_NAME__|${OS_NAME}|g; s|__BRAND_API__|${API_DOMAIN}|g" \
            "${TARGET_DIR}/usr/lib/systemd/system/${svc_file}.service"
    fi
done

# Patch NetworkManager config placeholder
if [ -f "${TARGET_DIR}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf" ]; then
    sed -i "s|__BRAND_API__|${API_DOMAIN}|g" \
        "${TARGET_DIR}/etc/NetworkManager/conf.d/00-${BRAND}-network.conf"
fi

echo "${OS_NAME}: Post-build configuration complete"
