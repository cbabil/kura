#!/bin/bash
# scripts/common/issue.sh
# The console login screen (/etc/issue, ADR-018), in the look of the README
# banner (.github/banner.html). The Linux console only has 16 colours and no
# CJK glyphs, so the screen first re-colours the palette with the console's
# "ESC ] P n RRGGBB" escape (navy background, Kura purples, light text, muted
# grey) and draws with block, box-drawing and middle-dot characters only.
# agetty fills the backslash escapes (\n host, \4 IPv4, \S{...} os-release,
# \m architecture, \d \t date and time) when it shows the prompt.
# Source this file; it defines functions only.

# kura_issue <tagline> [brand-colour]: the screen, on stdout; the brand
# colour is hex without '#' (OS_COLOR, default 9146ff)
kura_issue() {
    local esc=$'\033'
    local palette="" entry
    # index:colour — 0 background, 7 text, 5/D purple and light purple,
    # 8 muted, F white
    for entry in 0:0f172a 7:e2e8f0 "5:${2:-9146ff}" D:a970ff 8:94a3b8 F:ffffff; do
        palette+="${esc}]P${entry%%:*}${entry#*:}"
    done
    local purple="${esc}[0;35m" light="${esc}[0;95m" text="${esc}[0;37m"
    local bright="${esc}[0;97m" muted="${esc}[0;90m" reset="${esc}[0;37;40m"
    local rule="────────────────────────────────────────────────"

    printf '%s%s%s[2J%s[H\n' "${palette}" "${reset}" "${esc}" "${esc}"
    printf '%s' "${purple}"
    # The same logo as scripts/common/motd/05-ssh-banner
    cat <<'LOGO'
    ██   ██ ██    ██ ██████   █████
    ██  ██  ██    ██ ██   ██ ██   ██
    █████   ██    ██ ██████  ███████
    ██  ██  ██    ██ ██   ██ ██   ██
    ██   ██  ██████  ██   ██ ██   ██
LOGO
    printf '\n    %sT H E   S T O R E H O U S E\n' "${light}"
    printf '    %s%s\n\n' "${text}" "$1"
    printf '    %s%s\n' "${muted}" "${rule}"
    printf '    %sHost      %s\\n\n' "${muted}" "${bright}"
    printf '    %sAddress   %s\\4\n' "${muted}" "${bright}"
    printf '    %sConnect   %sssh <user>@\\4\n' "${muted}" "${bright}"
    printf '    %sSystem    %s\\S{PRETTY_NAME} · \\m\n' "${muted}" "${text}"
    printf '    %s%s\n' "${muted}" "${rule}"
    printf '    %s\\d · \\t%s\n\n' "${muted}" "${reset}"
}
