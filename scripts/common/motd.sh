#!/bin/bash
# scripts/common/motd.sh
# The message after login, laid out as Ubuntu's: a welcome line, where to
# look things up, the system information in two columns, then notices
# (updates, failed services, a pending restart). Plain text; every line fits
# 80 columns.
#
# Facts come from MOTD_* variables, which motd/10-status gathers on the
# device:
#   MOTD_WELCOME  "Kura 0.4.2 (Debian GNU/Linux 13, kernel ... x86_64)"
#   MOTD_DATE     "Tue Nov 10 17:02:31 UTC 2026"
#   MOTD_LEFT, MOTD_RIGHT  arrays of "Label:|value", one column each
#   MOTD_UPDATES  when updates last ran ("Nov 10 04:30"), empty if never
#   MOTD_FAILED   failed units         MOTD_REBOOT  restart time, empty if none
# Widths are counted in characters: callers set LC_ALL=C.UTF-8.
# Source this file; it defines functions only.

MOTD_DOCS="https://github.com/cbabil/kura"

# motd_label_width <items...>: the longest label, plus a space
motd_label_width() {
    local item width=0 label
    for item in "$@"; do
        label="${item%%|*}"
        [ "${#label}" -lt "${width}" ] || width=${#label}
    done
    echo $(( width + 1 ))
}

# motd_value_width <items...>: the longest value, plus the gap before the
# right column
motd_value_width() {
    local item width=0 value
    for item in "$@"; do
        value="${item#*|}"
        [ "${#value}" -lt "${width}" ] || width=${#value}
    done
    echo $(( width + 4 ))
}

# motd_columns: MOTD_LEFT and MOTD_RIGHT side by side, labels aligned
motd_columns() {
    local lw vw rw i left right rows=${#MOTD_LEFT[@]}
    lw=$(motd_label_width "${MOTD_LEFT[@]}")
    vw=$(motd_value_width "${MOTD_LEFT[@]}")
    rw=$(motd_label_width "${MOTD_RIGHT[@]}")
    [ "${#MOTD_RIGHT[@]}" -le "${rows}" ] || rows=${#MOTD_RIGHT[@]}
    for (( i = 0; i < rows; i++ )); do
        left="${MOTD_LEFT[i]:-|}" right="${MOTD_RIGHT[i]:-|}"
        printf '  %-*s%-*s%-*s%s\n' "${lw}" "${left%%|*}" "${vw}" "${left#*|}" \
            "${rw}" "${right%%|*}" "${right#*|}" | sed 's/[[:space:]]*$//'
    done
}

# motd_render: the message, on stdout
motd_render() {
    echo
    echo "Welcome to ${MOTD_WELCOME:-Kura}"
    echo
    echo " * Documentation:  ${MOTD_DOCS}"
    echo " * Containers:     docker ps"
    echo " * Logs:           journalctl -u <service>"
    echo
    echo " System information as of ${MOTD_DATE:-$(date)}"
    echo
    motd_columns
    echo
    if [ -n "${MOTD_UPDATES:-}" ]; then
        echo "Security updates install themselves daily; the last run was ${MOTD_UPDATES}."
    else
        echo "Security updates install themselves daily; they haven't run yet."
    fi
    case "${MOTD_FAILED:-0}" in
        0) ;;
        1) printf '\n1 service has failed: systemctl --failed\n' ;;
        *) printf '\n%s services have failed: systemctl --failed\n' "${MOTD_FAILED}" ;;
    esac
    [ -z "${MOTD_REBOOT:-}" ] ||
        printf '\n*** System restart required *** (it restarts by itself at %s)\n' "${MOTD_REBOOT}"
    echo
}

# ---- facts ----

# motd_gb <bytes>: decimal gigabytes with one decimal, as drives are sold
motd_gb() { local t=$(( $1 / 100000000 )); echo "$(( t / 10 )).$(( t % 10 ))"; }

# motd_percent <part> <whole>: a whole percent, rounded; 0% of nothing
motd_percent() {
    [ "$2" -gt 0 ] || { echo "0%"; return 0; }
    echo "$(( ($1 * 100 + $2 / 2) / $2 ))%"
}

# motd_meminfo <meminfo>: "<memory used> <swap used>", swap empty without swap
motd_meminfo() {
    local total avail swap swapfree
    read -r total avail swap swapfree < <(awk '
        /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
        /^SwapTotal:/ { s = $2 } /^SwapFree:/ { f = $2 }
        END { print t + 0, a + 0, s + 0, f + 0 }' "$1")
    printf '%s %s\n' "$(motd_percent $(( total - avail )) "${total}")" \
        "$([ "${swap}" -eq 0 ] || motd_percent $(( swap - swapfree )) "${swap}")"
}
