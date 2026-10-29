#!/bin/bash
# scripts/common/issue.sh
# The console login screen (/etc/issue), layout B (ADR-018, ADR-019): the big
# KURA logo, THE STOREHOUSE and the tagline on the left, a panel on the right
# with host, address, how to connect, system, uptime and disk, the services
# and the outcome of the imager's setup. Narrower than 116 columns, the panel
# goes under the logo.
#
# The Linux console has 16 colours and no CJK glyphs, so the screen first
# re-colours the palette with the console's "ESC ] P n RRGGBB" escape and
# draws with block, box-drawing, middle-dot, bullet and triangle characters
# only (Terminus Uni3, set in customize-rootfs.sh). agetty fills the
# backslash escapes (\n host, \4 IPv4, \S{...} os-release, \m architecture,
# \d \t date and time) at the prompt, so those are always current.
#
# Facts come from LOGIN_* variables; kura-issue sets them at runtime, and at
# build time they are empty, so the panel shows what agetty knows:
#   LOGIN_USER      login user name         LOGIN_VERSION  "Kura 0.4.2"
#   LOGIN_UPTIME    "3 min · disk 3% used"  LOGIN_COLS     console width
#   LOGIN_SERVICES  "docker:active ssh:failed ..."
#   LOGIN_SETUP     "applied", "ignored: <reason>", ... or empty
#   LOGIN_PASSWORD  the one-time password, until the owner changed it
# Source this file; it defines functions and constants only.

ISSUE_LOGO=(
    "██   ██ ██    ██ ██████   █████ "
    "██  ██  ██    ██ ██   ██ ██   ██"
    "█████   ██    ██ ██████  ███████"
    "██  ██  ██    ██ ██   ██ ██   ██"
    "██   ██  ██████  ██   ██ ██   ██"
)
ISSUE_LOGO_WIDTH=32
# The left column's width; its lines are padded to it so the panel's edge
# lines up (widths are passed in: a C locale counts a block as 3 bytes)
ISSUE_LEFT_WIDTH=44
# Narrower consoles get the panel under the logo (the widest panel line ends
# near column 114)
ISSUE_SIDE_BY_SIDE_COLS=116
# Kept in step with DEFAULT_TAGLINE in brand-defaults.sh
ISSUE_TAGLINE="The lightweight OS for your home server."

# Colours: palette entries set by issue_palette
ISSUE_PURPLE=$'\e[0;35m'
ISSUE_LIGHT=$'\e[0;95m'
ISSUE_TEXT=$'\e[0;37m'
ISSUE_BRIGHT=$'\e[0;97m'
ISSUE_MUTED=$'\e[0;90m'
ISSUE_GREEN=$'\e[0;32m'
ISSUE_RED=$'\e[0;31m'
ISSUE_AMBER=$'\e[0;33m'
ISSUE_RESET=$'\e[0;37;40m'

# issue_palette <brand-hex>: the console palette — 0 background, 1 red,
# 2 green, 3 amber, 5/D purple and light purple, 7 text, 8 muted, F white
issue_palette() {
    local entry
    for entry in 0:0f172a 1:ef4444 2:23ce6b 3:f59e0b "5:$1" D:a970ff 7:e2e8f0 8:94a3b8 F:ffffff; do
        printf '\e]P%s%s' "${entry%%:*}" "${entry#*:}"
    done
}

# issue_left_line <colour> <text> <width>: one left-column line, padded
issue_left_line() {
    local pad=$(( ISSUE_LEFT_WIDTH - $3 ))
    [ "${pad}" -ge 0 ] || pad=0
    printf '%s%s%*s\n' "$1" "$2" "${pad}" ""
}

# issue_left <tagline>: the left column, one line each (logo, kicker, tagline)
issue_left() {
    local i colour
    for i in "${!ISSUE_LOGO[@]}"; do
        # light purple at the top, the brand purple below (as on the splash)
        colour="${ISSUE_PURPLE}"
        [ "${i}" -lt 2 ] && colour="${ISSUE_LIGHT}"
        issue_left_line "${colour}" "${ISSUE_LOGO[i]}" "${ISSUE_LOGO_WIDTH}"
    done
    issue_left_line "" "" 0
    issue_left_line "${ISSUE_LIGHT}" "T H E   S T O R E H O U S E" 27
    # The tagline over two lines, split before "for your" when it has one
    local first="${1% for your *}" rest
    rest="${1#"${first}"}"
    rest="${rest# }"
    issue_left_line "${ISSUE_TEXT}" "${first}" "${#first}"
    [ -z "${rest}" ] || issue_left_line "${ISSUE_TEXT}" "${rest}" "${#rest}"
}

# issue_bar [text]: a panel line, its edge in muted grey
issue_bar() { printf '%s│%s\n' "${ISSUE_MUTED}" "${1:+  $1}"; }

# issue_row <label> <value-colour> <value>
issue_row() { issue_bar "$(printf '%-10s%s%s' "$1" "$2" "$3")"; }

# issue_panel: the right panel, one line each
issue_panel() {
    local rule="────────────────────────────────────────────────────────"
    local system='\S{PRETTY_NAME} · \m'
    [ -z "${LOGIN_VERSION:-}" ] || system="${LOGIN_VERSION} · ${system}"
    printf '%s┌%s\n' "${ISSUE_MUTED}" "${rule}"
    issue_bar
    issue_row Host "${ISSUE_BRIGHT}" '\n'
    issue_row Address "${ISSUE_BRIGHT}" '\4'
    issue_row Connect "${ISSUE_LIGHT}" "ssh ${LOGIN_USER:-<user>}@\\4"
    [ -z "${LOGIN_PASSWORD:-}" ] ||
        issue_row Password "${ISSUE_AMBER}" "${LOGIN_PASSWORD} · one-time, choose yours at login"
    issue_row System "${ISSUE_TEXT}" "${system}"
    [ -z "${LOGIN_UPTIME:-}" ] || issue_row Uptime "${ISSUE_TEXT}" "${LOGIN_UPTIME}"
    [ -z "${LOGIN_SERVICES:-}${LOGIN_SETUP:-}" ] || issue_bar
    if [ -n "${LOGIN_SERVICES:-}" ]; then
        local line="" entry dot
        for entry in ${LOGIN_SERVICES}; do
            dot="${ISSUE_RED}"
            [ "${entry#*:}" = active ] && dot="${ISSUE_GREEN}"
            line+="${dot}•${ISSUE_TEXT} ${entry%%:*}   "
        done
        issue_bar "${line%   }"
    fi
    case "${LOGIN_SETUP:-}" in
        "") ;;
        applied) issue_bar "${ISSUE_GREEN}•${ISSUE_TEXT} setup applied" ;;
        *)  # "ignored: <reason>": the reason on its own line, so it fits
            issue_bar "${ISSUE_AMBER}▲ setup ${LOGIN_SETUP%%:*}"
            [ "${LOGIN_SETUP#*: }" = "${LOGIN_SETUP}" ] ||
                issue_bar "  ${ISSUE_AMBER}${LOGIN_SETUP#*: }" ;;
    esac
    issue_bar
    printf '%s└%s\n' "${ISSUE_MUTED}" "${rule}"
}

# kura_issue [tagline] [brand-hex]: the screen, on stdout; the colour default
# is DEFAULT_COLOR in brand-defaults.sh, which the image does not carry
kura_issue() {
    local tagline="${1:-${ISSUE_TAGLINE}}" colour="${2:-9146ff}" pad="      "
    local -a left panel
    local line i blank
    while IFS= read -r line; do left+=("${line}"); done < <(issue_left "${tagline}")
    while IFS= read -r line; do panel+=("${line}"); done < <(issue_panel)
    printf -v blank '%*s' "${ISSUE_LEFT_WIDTH}" ""

    issue_palette "${colour}"
    printf '%s\e[2J\e[H\n' "${ISSUE_RESET}"
    if [ "${LOGIN_COLS:-120}" -ge "${ISSUE_SIDE_BY_SIDE_COLS}" ]; then
        # Side by side: the panel starts at column 50
        for (( i = 0; i < ${#left[@]} || i < ${#panel[@]}; i++ )); do
            printf '%s%s%s\n' "${pad}" "${left[i]:-${blank}}" "${panel[i]:-}"
        done
    else
        for line in "${left[@]}" "" "${panel[@]}"; do printf '%s%s\n' "${pad}" "${line}"; done
    fi
    printf '\n%s%s\\d · \\t · log in below, or connect with SSH from another computer%s\n\n' \
        "${pad}" "${ISSUE_MUTED}" "${ISSUE_RESET}"
}
