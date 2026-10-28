#!/bin/bash
# scripts/pc-installer/ui.sh
# The PC installer's screen (ADR-017), in the look of the login screen
# (scripts/common/issue.sh): the console palette re-coloured with
# "ESC ] P n RRGGBB", the KURA logo, the installer's steps, bands and bars.
# The Linux console has 16 colours, no bright backgrounds and no CJK glyphs,
# so the screen only uses backgrounds 0-7 and block, shade, box-drawing,
# middle-dot, √, › and ▲ characters. Pure functions: each prints its part on
# stdout and the callers (install.sh, init) redraw the whole screen per
# state. Source this file; it defines functions only.

UI_PAD="    "
# Save and restore the cursor (ESC 7, ESC 8), for parts redrawn in place
# shellcheck disable=SC2034  # used by screen.sh and run.sh
UI_SAVE=$'\0337'
# shellcheck disable=SC2034
UI_RESTORE=$'\0338'
UI_STEPS=("USB key" "Network" "Release" "Internal drive" "Write and check" "Hand over your setup")

# ui_color <fg> [bg]: SGR for palette indices given as hex digits; bold is
# reset each time, as the console's bright colours are bold ones
ui_color() {
    local fg=$(( 16#$1 )) code
    if [ "${fg}" -lt 8 ]; then code="0;$(( 30 + fg ))"; else code="0;$(( 82 + fg ))"; fi
    [ -n "${2:-}" ] && code+=";$(( 40 + 16#$2 ))"
    printf '\033[%sm' "${code}"
}

# ui_repeat <char> <count>
ui_repeat() {
    local i
    for (( i = 0; i < $2; i++ )); do printf '%s' "$1"; done
}

# ui_palette [brand-colour]: index:colour: 0 background, 7 text, 5/D purple
# and light purple, 8 muted, 9 rules and empty bars, 2 green, 3 amber,
# 1 red, 4 panel, E band, F white
ui_palette() {
    local entry
    for entry in 0:0f172a 7:e2e8f0 "5:${1:-9146ff}" D:a970ff 8:94a3b8 9:334155 2:23ce6b \
            3:f59e0b 1:ef4444 4:1e293b E:2a1f55 F:ffffff; do
        printf '\033]P%s%s' "${entry%%:*}" "${entry#*:}"
    done
}

# ui_clear: background colour, empty screen, cursor home and hidden
ui_clear() { printf '\033[0;37;40m\033[2J\033[H\033[?25l'; }

# ui_header: the logo, light to brand purple, its captions and a rule
ui_header() {
    local logo=(
        "██   ██ ██    ██ ██████   █████ "
        "██  ██  ██    ██ ██   ██ ██   ██"
        "█████   ██    ██ ██████  ███████"
        "██  ██  ██    ██ ██   ██ ██   ██"
        "██   ██  ██████  ██   ██ ██   ██")
    local shades=(D D 5 5 5) i side
    printf '\n\n'
    for i in 0 1 2 3 4; do
        case "${i}" in
            1) side="$(ui_color D)T H E   S T O R E H O U S E" ;;
            3) side="$(ui_color F)Installer$(ui_color 8)  ·  puts Kura on this PC's internal drive" ;;
            *) side="" ;;
        esac
        printf '%s%s%s      %s\n' "${UI_PAD}" "$(ui_color "${shades[i]}")" "${logo[i]}" "${side}"
    done
    printf '\n%s%s%s\n\n' "${UI_PAD}" "$(ui_color 9)" "$(ui_repeat ─ 104)"
}

# ui_steps <current> <detail>...: the six steps, before <current> done (√
# green), <current> in progress (› purple), the rest to come (· grey,
# without their detail); a <current> past the last means all done
ui_steps() {
    local current=$1 i
    shift
    for (( i = 1; i <= ${#UI_STEPS[@]}; i++ )); do
        if [ "${i}" -lt "${current}" ]; then
            printf '%s%s√  %s%-28s%s%s\n' "${UI_PAD}" "$(ui_color 2)" "$(ui_color 7)" \
                "${UI_STEPS[i - 1]}" "$(ui_color 8)" "$1"
        elif [ "${i}" -eq "${current}" ]; then
            printf '%s%s›  %s%-28s%s%s\n' "${UI_PAD}" "$(ui_color D)" "$(ui_color F)" \
                "${UI_STEPS[i - 1]}" "$(ui_color D)" "$1"
        else
            printf '%s%s·  %s%s\n' "${UI_PAD}" "$(ui_color 9)" "$(ui_color 8)" "${UI_STEPS[i - 1]}"
        fi
        shift || true
    done
}

# ui_bar <value> <total> <width>: █ purple for value/total of the width,
# ░ grey for the rest
ui_bar() {
    local full=0
    [ "$2" -gt 0 ] && full=$(( $3 * $1 / $2 ))
    [ "${full}" -gt "$3" ] && full=$3
    printf '%s%s%s%s' "$(ui_color 5)" "$(ui_repeat █ "${full}")" \
        "$(ui_color 9)" "$(ui_repeat ░ $(( $3 - full )))"
}

# ui_line <colour> <text>: one indented line
ui_line() { printf '%s%s%s\n' "${UI_PAD}" "$(ui_color "$1")" "$2"; }

# ui_note <text>: a muted line
ui_note() { ui_line 8 "$1"; }

# ui_warning <text>: amber on the panel colour
ui_warning() { printf '%s%s  ▲  %s  %s\n' "${UI_PAD}" "$(ui_color 3 4)" "$1" "$(ui_color 7 0)"; }

# ui_done <text>: navy on green
ui_done() { printf '%s%s  √  %s  %s\n' "${UI_PAD}" "$(ui_color 0 2)" "$1" "$(ui_color 7 0)"; }

# ui_error <text>: red, lines after the first indented with it
ui_error() { printf '\n%s%s▲  %s%s\n' "${UI_PAD}" "$(ui_color 1)" "${1//$'\n'/$'\n'${UI_PAD}   }" "$(ui_color 7)"; }
