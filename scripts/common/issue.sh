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
# only (Terminus, the set chosen in customize-rootfs.sh). agetty fills the
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
#   LOGIN_UPGRADE   "Kura 0.6.1" when that version is in the repository
#   LOGIN_RESTART   non-empty when an update needs a restart
# Source this file; it defines functions and constants only.

ISSUE_LOGO=(
    "██   ██ ██    ██ ██████   █████ "
    "██  ██  ██    ██ ██   ██ ██   ██"
    "█████   ██    ██ ██████  ███████"
    "██  ██  ██    ██ ██   ██ ██   ██"
    "██   ██  ██████  ██   ██ ██   ██"
)
ISSUE_LOGO_WIDTH=32
# 蔵, drawn in blocks, before the logo on consoles with the room
# shellcheck source=scripts/common/kanji.sh
source "$(dirname "${BASH_SOURCE[0]}")/kanji.sh"
# The left column's width, without and with the character; its lines are
# padded to it so the panel's edge lines up (widths are passed in: a C locale
# counts a block as 3 bytes)
ISSUE_LEFT_WIDTH=44
ISSUE_LEFT_WIDTH_KANJI=58
# Narrower consoles get the panel under the logo; wider ones than the second
# have room for the character beside the logo
ISSUE_SIDE_BY_SIDE_COLS=116
ISSUE_KANJI_COLS=140
# The panel: never narrower than its rule was, its text never wider
ISSUE_PANEL_MIN=52
ISSUE_PANEL_MAX=72
ISSUE_MARGIN=6
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

# issue_left_line <colour> <text> <width> <column-width>: one left-column
# line, padded to the column
issue_left_line() {
    local pad=$(( $4 - $3 ))
    [ "${pad}" -ge 0 ] || pad=0
    printf '%s%s%*s\n' "$1" "$2" "${pad}" ""
}

# issue_left <tagline> [kanji]: the left column, one line each: the logo
# (with the character before it, given the room), kicker and tagline
issue_left() {
    local i colour width="${ISSUE_LEFT_WIDTH}" kicker="T H E   S T O R E H O U S E"
    if [ -n "${2:-}" ]; then
        local beside
        width="${ISSUE_LEFT_WIDTH_KANJI}"
        for i in "${!KURA_KANJI[@]}"; do
            # light purple at the top, the brand purple below (as on the splash)
            colour="${ISSUE_PURPLE}"
            [ "${i}" -lt 4 ] && colour="${ISSUE_LIGHT}"
            beside=""
            if [ "${i}" -ge 2 ] && [ "${i}" -le 6 ]; then
                beside="${ISSUE_PURPLE}"
                [ "${i}" -lt 4 ] && beside="${ISSUE_LIGHT}"
                beside+="${ISSUE_LOGO[i - 2]}"
            elif [ "${i}" -eq 8 ]; then
                beside="${ISSUE_LIGHT}${kicker}"
            fi
            printf '%s%s  %s%*s\n' "${colour}" "${KURA_KANJI[i]}" "${beside}" \
                $(( width - KURA_KANJI_WIDTH - 2 - (i >= 2 && i <= 6 ? ISSUE_LOGO_WIDTH : i == 8 ? ${#kicker} : 0) )) ""
        done
    else
        for i in "${!ISSUE_LOGO[@]}"; do
            colour="${ISSUE_PURPLE}"
            [ "${i}" -lt 2 ] && colour="${ISSUE_LIGHT}"
            issue_left_line "${colour}" "${ISSUE_LOGO[i]}" "${ISSUE_LOGO_WIDTH}" "${width}"
        done
        issue_left_line "" "" 0 "${width}"
        issue_left_line "${ISSUE_LIGHT}" "${kicker}" "${#kicker}" "${width}"
    fi
    [ -z "${2:-}" ] || issue_left_line "" "" 0 "${width}"
    # The tagline over two lines, split before "for your" when it has one
    local first="${1% for your *}" rest
    rest="${1#"${first}"}"
    rest="${rest# }"
    issue_left_line "${ISSUE_TEXT}" "${first}" "${#first}" "${width}"
    [ -z "${rest}" ] || issue_left_line "${ISSUE_TEXT}" "${rest}" "${#rest}" "${width}"
}

# issue_plain <text>: without its colour escapes
issue_plain() {
    local rest="$1" out=""
    while [[ "${rest}" == *$'\e['* ]]; do
        out+="${rest%%$'\e['*}"
        rest="${rest#*$'\e['}"
        rest="${rest#*m}"
    done
    printf '%s' "${out}${rest}"
}

# issue_text <indent> <colour> <text> <width>: plain text as panel lines,
# wrapped at spaces to <width>, later lines under the first one's text
issue_text() {
    local indent first=1 line
    printf -v indent '%*s' "$1" ""
    while IFS= read -r line; do
        printf '%s%s%s\n' "${indent}" "$2" "${line% }"
        first=0
    done < <(fold -s -w $(( $4 - $1 )) <<< "$3")
}

# issue_row <label> <value-colour> <value> <width>: a label, and its value
# (wrapped under itself when it is too long)
issue_row() {
    local first=1 line
    while IFS= read -r line; do
        if [ "${first}" -eq 1 ]; then printf '%-10s%s\n' "$1" "${line}"; else printf '%s\n' "${line}"; fi
        first=0
    done < <(issue_text 0 "$2" "$3" $(( $4 - 10 )) | sed '2,$s/^/          /')
}

# issue_short_fp <AA:BB:...>: the first and last four bytes, enough to
# compare with the browser's certificate details (plain dots between: the
# console font has no ellipsis)
issue_short_fp() { printf '%s .. %s' "${1:0:11}" "${1: -11}"; }

# issue_panel_lines <width>: what the panel says, one line each, none wider
# than <width>. LOGIN_HOST set means kura-issue gave this device's own name,
# address and system; without it (the screen built into the image) agetty
# fills them in at the prompt.
issue_panel_lines() {
    local w="$1" address='\4' system='\S{PRETTY_NAME} · \m'
    [ -z "${LOGIN_SYSTEM:-}" ] || system="${LOGIN_SYSTEM}"
    [ -z "${LOGIN_VERSION:-}" ] || system="${LOGIN_VERSION} · ${system}"
    [ -z "${LOGIN_HOST:-}" ] || address="${LOGIN_ADDRESS:-}"
    echo
    issue_row Host "${ISSUE_BRIGHT}" "${LOGIN_HOST:-\\n}" "${w}"
    if [ -n "${address}" ]; then
        issue_row Address "${ISSUE_BRIGHT}" "${address}" "${w}"
        issue_row Connect "${ISSUE_LIGHT}" "ssh ${LOGIN_USER:-<user>}@${address}" "${w}"
    else
        issue_row Address "${ISSUE_AMBER}" "none yet" "${w}"
    fi
    if [ -n "${LOGIN_DESKTOP_FP:-}" ]; then   # Kura Desktop (ADR-023)
        [ -z "${address}" ] || issue_row Desktop "${ISSUE_LIGHT}" "https://${address}" "${w}"
        issue_row Cert "${ISSUE_TEXT}" "SHA-256 $(issue_short_fp "${LOGIN_DESKTOP_FP}")" "${w}"
    fi
    [ -z "${LOGIN_PASSWORD:-}" ] ||
        issue_row Password "${ISSUE_AMBER}" "${LOGIN_PASSWORD} · one-time, choose yours at login" "${w}"
    issue_row System "${ISSUE_TEXT}" "${system}" "${w}"
    [ -z "${LOGIN_UPTIME:-}" ] || issue_row Uptime "${ISSUE_TEXT}" "${LOGIN_UPTIME}" "${w}"
    [ -z "${LOGIN_SERVICES:-}${LOGIN_SETUP:-}${LOGIN_UPGRADE:-}${LOGIN_RESTART:-}" ] || echo
    if [ -n "${LOGIN_SERVICES:-}" ]; then
        local line="" entry dot
        for entry in ${LOGIN_SERVICES}; do
            dot="${ISSUE_RED}"
            [ "${entry#*:}" = active ] && dot="${ISSUE_GREEN}"
            line+="${dot}•${ISSUE_TEXT} ${entry%%:*}   "
        done
        echo "${line%   }"
    fi
    case "${LOGIN_SETUP:-}" in
        "") ;;
        applied) echo "${ISSUE_GREEN}•${ISSUE_TEXT} setup applied" ;;
        *)  # "ignored: <reason>": the reason on its own lines, wrapped
            echo "${ISSUE_AMBER}▲ setup ${LOGIN_SETUP%%:*}"
            [ "${LOGIN_SETUP#*: }" = "${LOGIN_SETUP}" ] ||
                issue_text 2 "${ISSUE_AMBER}" "${LOGIN_SETUP#*: }" "${w}" ;;
    esac
    # What waits for the owner (ADR-025): a new version, a restart
    if [ -n "${LOGIN_UPGRADE:-}" ]; then
        echo "${ISSUE_AMBER}▲ ${LOGIN_UPGRADE} available"
        issue_text 2 "${ISSUE_AMBER}" "sudo apt update && sudo apt full-upgrade" "${w}"
    fi
    [ -z "${LOGIN_RESTART:-}" ] || echo "${ISSUE_AMBER}▲ restart required · sudo reboot"
    echo
}

# issue_panel <width>: the panel as a box sized to what it holds. With the
# device's own facts every width is known and the box is closed; agetty's
# escapes have none, so the image's built-in screen keeps its right side open.
issue_panel() {
    local closed="${LOGIN_HOST:+1}" line plain width="${ISSUE_PANEL_MIN}" rule=""
    local -a lines
    while IFS= read -r line; do
        lines+=("${line}")
        plain=$(issue_plain "${line}")
        [ "${#plain}" -le "${width}" ] || width=${#plain}
    done < <(issue_panel_lines "$1")
    printf -v rule '%*s' $(( width + 4 )) ""
    rule="${rule// /─}"
    printf '%s┌%s%s\n' "${ISSUE_MUTED}" "${rule}" "${closed:+┐}"
    for line in "${lines[@]}"; do
        plain=$(issue_plain "${line}")
        if [ -n "${closed}" ]; then
            printf '%s│  %s%*s  %s│\n' "${ISSUE_MUTED}" "${line}" $(( width - ${#plain} )) "" "${ISSUE_MUTED}"
        else
            printf '%s│%s\n' "${ISSUE_MUTED}" "${line:+  ${line}}"
        fi
    done
    printf '%s└%s%s\n' "${ISSUE_MUTED}" "${rule}" "${closed:+┘}"
}

# kura_issue [tagline] [brand-hex]: the screen, on stdout; the colour default
# is DEFAULT_COLOR in brand-defaults.sh, which the image does not carry
kura_issue() {
    local tagline="${1:-${ISSUE_TAGLINE}}" colour="${2:-9146ff}" cols="${LOGIN_COLS:-120}"
    local -a left panel
    local line i blank pad kanji="" left_width="${ISSUE_LEFT_WIDTH}" side="" room box total margin="${ISSUE_MARGIN}"
    [ "${cols}" -lt "${ISSUE_SIDE_BY_SIDE_COLS}" ] || side=1
    if [ "${cols}" -ge "${ISSUE_KANJI_COLS}" ]; then kanji=1; left_width="${ISSUE_LEFT_WIDTH_KANJI}"; fi
    # the room for the panel's text: the console less the left margin, two
    # columns on the right, the left column when beside it, and the box's own
    # edges and padding
    room=$(( cols - ISSUE_MARGIN - 2 - 6 - (side ? left_width : 0) ))
    [ "${room}" -le "${ISSUE_PANEL_MAX}" ] || room="${ISSUE_PANEL_MAX}"
    while IFS= read -r line; do left+=("${line}"); done < <(issue_left "${tagline}" "${kanji}")
    while IFS= read -r line; do panel+=("${line}"); done < <(issue_panel "${room}")
    printf -v blank '%*s' "${left_width}" ""
    # With the device's own facts the screen's width is known: centred
    if [ -n "${LOGIN_HOST:-}" ]; then
        box=$(issue_plain "${panel[0]}")
        total=$(( side ? left_width + ${#box} : (left_width > ${#box} ? left_width : ${#box}) ))
        [ $(( (cols - total) / 2 )) -le "${margin}" ] || margin=$(( (cols - total) / 2 ))
    fi
    printf -v pad '%*s' "${margin}" ""

    issue_palette "${colour}"
    printf '%s\e[2J\e[H\n' "${ISSUE_RESET}"
    if [ -n "${side}" ]; then
        for (( i = 0; i < ${#left[@]} || i < ${#panel[@]}; i++ )); do
            printf '%s%s%s\n' "${pad}" "${left[i]:-${blank}}" "${panel[i]:-}"
        done
    else
        for line in "${left[@]}" "" "${panel[@]}"; do printf '%s%s\n' "${pad}" "${line}"; done
    fi
    printf '\n%s%s\\d · \\t · log in below, or connect with SSH from another computer%s\n\n' \
        "${pad}" "${ISSUE_MUTED}" "${ISSUE_RESET}"
    # the login prompt under the screen, not at the console's edge
    [ "${margin}" -le "${ISSUE_MARGIN}" ] || printf '%s' "${pad}"
}
