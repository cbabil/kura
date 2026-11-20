#!/bin/bash
# desktop/ci/api.sh — Kura Desktop's HTTP contract for shell tests: the
# sign-in body, a request's status, the CSRF header and the memory budget.
# Sourced by desktop/ci/e2e.sh (the server alone, in CI) and
# tests/boot/desktop-checks.sh (a booted image); defines functions only.

# shellcheck disable=SC2034  # read by the scripts that source this file
DESKTOP_RSS_MAX_KIB=40960   # 40 MB resident (ADR-023)
# shellcheck disable=SC2034
DESKTOP_CHANGE=(-H 'x-kura-request: 1')                              # requests that change something
# shellcheck disable=SC2034
DESKTOP_POST=(-X POST -H 'content-type: application/json' --data @-) # JSON body on stdin

# desktop_login_body <user> <password>: the sign-in body on stdout, so the
# password never appears in a command line
desktop_login_body() { jq -nc --arg u "$1" --arg p "$2" '{user: $u, password: $p}'; }

# desktop_code <origin> <curl args...>: the HTTP status of a request sent
# from <origin> (the server accepts changes only from its own origin)
desktop_code() {
    local origin="$1"
    shift
    curl -sk --max-time 10 -o /dev/null -w '%{http_code}' -H "Origin: ${origin}" "$@"
}
