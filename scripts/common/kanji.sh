#!/bin/bash
# scripts/common/kanji.sh — 蔵 (kura, the storehouse), drawn in half blocks:
# the console font has no Japanese glyphs. Each row is two rows of screen
# pixels, 20 x 18 in all (ADR-026). Shared by the login screen (issue.sh) and
# the PC installer (ui.sh), installed next to each. Defines constants only.

# shellcheck disable=SC2034  # read by the scripts sourcing this file
KURA_KANJI=(
    "     ██      ██     "
    "▀▀▀▀▀██▀▀▀▀▀▀██▀▀▀▀▀"
    "  ▄▄         ██ ▀█▄ "
    "  ██▀▀▀▀▀▀▀▀▀██▀▀▀▀ "
    "  ██ ██▀▀██▀▀ ██ ██ "
    "  ██ ██▀▀██▀█▄▀███  "
    "  ██ ██▀▀██▀▀ ▄██▄  "
    " ▄█▀ ▀▀▀▀▀▀▀▀▄█▀ ██▄"
    "▄█▀        ▄█▀   ▀██"
)
# shellcheck disable=SC2034
KURA_KANJI_WIDTH=20
