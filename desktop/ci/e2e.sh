#!/usr/bin/env bash
# End-to-end check of Kura Desktop on a Linux CI runner: kura-helper as root on
# the system bus behind the real D-Bus policy, kura-desktopd (no dev-auth) on
# HTTPS with a throwaway certificate, sign-in through PAM, the API and the
# stats WebSocket, and desktopd's memory. Run from desktop/ after
# `cargo build --release`; needs sudo, openssl and curl.
# Usage: ci/e2e.sh <user> <password>
set -euo pipefail

user="$1"
password="$2"
bin="target/release"
state="$(mktemp -d)"
base="https://localhost:8443"
policy=/etc/dbus-1/system.d/io.kura.Helper.conf

cleanup() {
    sudo pkill -f "${bin}/kura-helper" || true
    pkill -f "${bin}/kura-desktopd" || true
    sudo rm -f "${policy}"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# The policy names the kura-desktop user; here desktopd runs as the CI user.
sed "s/user=\"kura-desktop\"/user=\"$(id -un)\"/" packaging/dbus/io.kura.Helper.conf | sudo tee "${policy}" >/dev/null
sudo systemctl reload dbus
sudo "${bin}/kura-helper" &
sleep 1

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost -keyout "${state}/tls.key" -out "${state}/tls.crt" 2>/dev/null
"${bin}/kura-desktopd" --listen 127.0.0.1:8443 --state-dir "${state}" &
desktopd=$!
sleep 2

# status <expected> <curl args...>: asserts the HTTP status of a request.
status() {
    local want="$1" got
    shift
    got="$(curl -sk -o /dev/null -w '%{http_code}' -H "Origin: ${base}" "$@")"
    [ "${got}" = "${want}" ] || fail "$* gave ${got}, wanted ${want}"
}

login() {
    printf '{"user":"%s","password":"%s"}' "$1" "$2"
}

status 401 "${base}/api/session"
status 403 -X POST -H 'content-type: application/json' --data "$(login "${user}" "${password}")" "${base}/api/login"
status 401 -X POST -H 'x-kura-request: 1' -H 'content-type: application/json' \
    --data "$(login "${user}" wrong)" "${base}/api/login"
jar="${state}/cookies"
status 200 -c "${jar}" -X POST -H 'x-kura-request: 1' -H 'content-type: application/json' \
    --data "$(login "${user}" "${password}")" "${base}/api/login"
status 200 -b "${jar}" "${base}/api/session"
curl -sk -b "${jar}" "${base}/api/system" | grep -q '"cores":[1-9]' || fail "/api/system has no cores"

stream="$(curl -sk -i -N --http1.1 --max-time 3 -b "${jar}" -H "Origin: ${base}" \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' "${base}/api/stats" | tr -d '\0' || true)"
grep -q '101' <<<"${stream}" || fail "stats WebSocket was not accepted"
grep -q '"type":"snapshot"' <<<"${stream}" || fail "stats WebSocket sent no snapshot"

rss_kb="$(ps -o rss= -p "${desktopd}" | tr -d ' ')"
echo "kura-desktopd RSS: ${rss_kb} kB"
[ "${rss_kb}" -lt 40960 ] || fail "kura-desktopd uses ${rss_kb} kB, over the 40 MB budget"
echo "end-to-end: ok"
