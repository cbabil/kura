#!/usr/bin/env bash
# End-to-end check of Kura Desktop on a Linux CI runner: kura-helper as root on
# the system bus behind the real D-Bus policy, kura-desktopd (no dev-auth) on
# HTTPS with a throwaway certificate, sign-in through PAM, the API and the
# stats WebSocket, and desktopd's memory. Run from desktop/ after
# `cargo build --release` (`make e2e` does both); needs sudo, openssl, curl
# and jq.
# Usage: KURA_PAM_PASSWORD=<password> ci/e2e.sh <user>
set -euo pipefail

user="${1:?Usage: KURA_PAM_PASSWORD=<password> $0 <user>}"
password="${KURA_PAM_PASSWORD:?set KURA_PAM_PASSWORD to the password of the user}"
bin="target/release"
state="$(mktemp -d)"
base="https://localhost:8443"
policy=/etc/dbus-1/system.d/io.kura.Helper.conf

cleanup() {
    sudo pkill -f "${bin}/kura-helper" || true
    sudo pkill -f "${bin}/kura-desktopd" || true
    sudo rm -f "${policy}"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# As in the image: desktopd runs as kura-desktop, the only user the D-Bus
# policy and the helper itself accept as a caller.
id kura-desktop >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin kura-desktop
sed -e 's/__BRAND_NAME__/Kura/g' -e 's/__BRAND__/kura/g' ../packages/os-desktop/src/io.kura.Helper.conf \
    | sudo tee "${policy}" >/dev/null
sudo systemctl reload dbus
sudo "${bin}/kura-helper" &
sleep 1

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost -keyout "${state}/tls.key" -out "${state}/tls.crt" 2>/dev/null
sudo chown -R kura-desktop "${state}"
sudo -u kura-desktop env KURA_STATE_DIR="${state}" "${bin}/kura-desktopd" --listen 127.0.0.1:8443 &
sleep 2
desktopd="$(pgrep -u kura-desktop -f "${bin}/kura-desktopd")"

# shellcheck source=desktop/ci/api.sh
source "$(dirname "$0")/api.sh"

# status <expected> <curl args...>: asserts the HTTP status of a request.
status() {
    local want="$1" got
    shift
    got="$(desktop_code "${base}" "$@")"
    [ "${got}" = "${want}" ] || fail "$* gave ${got}, wanted ${want}"
}

status 401 "${base}/api/session"
desktop_login_body "${user}" "${password}" | status 403 "${DESKTOP_POST[@]}" "${base}/api/login"
desktop_login_body "${user}" wrong | status 401 "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
desktop_login_body root "${password}" | status 401 "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
jar="$(mktemp)"
desktop_login_body "${user}" "${password}" | status 200 -c "${jar}" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
status 200 -b "${jar}" "${base}/api/session"
curl -sk -b "${jar}" "${base}/api/system" | grep -q '"cores":[1-9]' || fail "/api/system has no cores"

stream="$(curl -sk -i -N --http1.1 --max-time 3 -b "${jar}" -H "Origin: ${base}" \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' "${base}/api/stats" | tr -d '\0' || true)"
grep -q '101' <<<"${stream}" || fail "stats WebSocket was not accepted"
grep -q '"type":"snapshot"' <<<"${stream}" || fail "stats WebSocket sent no snapshot"

rss_kb="$(ps -o rss= -p "${desktopd}" | tr -d ' ')"
echo "kura-desktopd RSS: ${rss_kb} kB"
[ "${rss_kb}" -lt "${DESKTOP_RSS_MAX_KIB}" ] || fail "kura-desktopd uses ${rss_kb} kB, over the 40 MB budget"
echo "end-to-end: ok"
