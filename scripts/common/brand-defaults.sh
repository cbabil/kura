#!/bin/bash
# scripts/common/brand-defaults.sh
# Single source of truth for default brand values.
# Source this file from any script that needs brand fallbacks.
#
# These values match the literal strings in source/template files.
# The build system seds them to the actual OS_* values at install time.

# shellcheck disable=SC2034
DEFAULT_BRAND="kura"
DEFAULT_NAME="Kura"
DEFAULT_COLOR="#9146FF"
DEFAULT_API_ENDPOINT="https://api.kura.io"
DEFAULT_WS_ENDPOINT=$(echo "${DEFAULT_API_ENDPOINT}" | sed 's|^http|ws|')/ws
DEFAULT_REGISTRY="registry.kura.io"
DEFAULT_WS_HEARTBEAT_INTERVAL="30000"
DEFAULT_WS_HEARTBEAT_TIMEOUT="90000"
DEFAULT_WS_RECONNECT_BASE="1000"
DEFAULT_WS_RECONNECT_MAX="60000"
DEFAULT_HOSTNAME="kura"
# Login user (SSH password auth, sudo). Its default password is public, so it
# is expired at build time (scripts/common/passwords.sh).
DEFAULT_USER="admin"
DEFAULT_USER_PASSWD="admin"
DEFAULT_TMP="/home/${DEFAULT_BRAND}/tmp"

# Derived domains (used in sed patterns for hardening.json, etc.)
DEFAULT_API_DOMAIN="${DEFAULT_API_ENDPOINT#*://}"
DEFAULT_BASE_DOMAIN="${DEFAULT_API_DOMAIN#*.}"
DEFAULT_UPDATES_DOMAIN="updates.${DEFAULT_BASE_DOMAIN}"
