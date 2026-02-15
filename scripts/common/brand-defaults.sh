#!/bin/bash
# scripts/common/brand-defaults.sh
# Single source of truth for default brand values.
# Source this file from any script that needs brand fallbacks.
#
# These values match the literal strings in source/template files.
# The build system seds them to the actual OS_* values at install time.

DEFAULT_BRAND="falken"
DEFAULT_NAME="FalkenOS"
DEFAULT_API_ENDPOINT="https://api.falken.io"
DEFAULT_REGISTRY="registry.falken.io"
DEFAULT_HOSTNAME="${DEFAULT_BRAND}os"
DEFAULT_ROOT_PASSWD="${DEFAULT_BRAND}"
DEFAULT_TMP="/home/${DEFAULT_BRAND}os/tmp"

# Derived domains (used in sed patterns for hardening.json, etc.)
DEFAULT_API_DOMAIN="${DEFAULT_API_ENDPOINT#*://}"
DEFAULT_BASE_DOMAIN="${DEFAULT_API_DOMAIN#*.}"
DEFAULT_UPDATES_DOMAIN="updates.${DEFAULT_BASE_DOMAIN}"
