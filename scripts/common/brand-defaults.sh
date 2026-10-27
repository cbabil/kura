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
# README banner tagline: login screen and SSH welcome (OS_ISSUE overrides)
DEFAULT_TAGLINE="The lightweight OS for your home server."
DEFAULT_HOSTNAME="kura"
# Login user (SSH password auth, sudo). Its default password is public, so it
# is expired at build time (scripts/common/passwords.sh).
DEFAULT_USER="admin"
DEFAULT_USER_PASSWD="admin"
DEFAULT_TMP="/home/${DEFAULT_BRAND}/tmp"
