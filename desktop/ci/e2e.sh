#!/usr/bin/env bash
# End-to-end check of Kura Desktop on a Linux CI runner: kura-helper as root on
# the system bus behind the real D-Bus policy, kura-desktopd (no dev-auth) on
# HTTPS with a throwaway certificate, sign-in through PAM, the API and the
# stats WebSocket, and desktopd's memory. Then the helper's D2 actions
# (ADR-027) against the runner's own systemd, Docker and journal: a terminal
# whose shell runs as the signed-in user, a container listed, restarted and
# read, the journal, and the refusals a user who is not an administrator
# gets. Run from desktop/ after `cargo build --release` (`make e2e` does
# both); needs sudo, openssl, curl, jq and Docker.
# Usage: KURA_PAM_PASSWORD=<password> ci/e2e.sh <administrator> [<other user>]
# Both users have that password; the first is in the sudo group.
set -euo pipefail

user="${1:?Usage: KURA_PAM_PASSWORD=<password> $0 <administrator> [<other user>]}"
guest="${2:-}"
password="${KURA_PAM_PASSWORD:?set KURA_PAM_PASSWORD to the password of the user}"
bin="target/release"
state="$(mktemp -d)"   # desktopd's own: handed to its user below
out="$(mktemp -d)"     # this script's own files
base="https://localhost:8443"
policy=/etc/dbus-1/system.d/io.kura.Helper.conf

cleanup() {
    [ -z "${work:-}" ] || sudo rm -rf "${work}"
    sudo rm -rf "${state}" "${out}"
    docker rm -f kura-e2e >/dev/null 2>&1 || true
    sudo systemctl stop kura-job-update.service >/dev/null 2>&1 || true
    sudo userdel -r kura-e2e-new >/dev/null 2>&1 || true
    sudo rm -rf /usr/lib/kura/kura-settings /usr/lib/kura/kura-settings-screens /usr/lib/kura/kura-apps /usr/lib/kura/catalog /usr/lib/kura/kura-agent /run/kura-helper
    sudo systemctl reset-failed kura-job-update.service >/dev/null 2>&1 || true
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
# The root command behind Settings and the helper's folder for password
# files, where the image has them
sed -e 's/__BRAND__/kura/g' ../packages/os-desktop/src/os-settings | sudo install -D -m 0755 /dev/stdin /usr/lib/kura/kura-settings
sed -e 's/__BRAND__/kura/g' ../packages/os-desktop/src/os-settings-screens | sudo install -D -m 0644 /dev/stdin /usr/lib/kura/kura-settings-screens
sudo install -d -m 0700 /run/kura-helper
# The App Catalog: its root command and templates
sed -e 's/__BRAND__/kura/g' ../packages/os-desktop/src/os-apps | sudo install -D -m 0755 /dev/stdin /usr/lib/kura/kura-apps
sudo cp -R ../packages/os-desktop/catalog /usr/lib/kura/catalog
# The file agent, which systemd runs as the signed-in user
sudo install -m 0755 "${bin}/kura-agent" /usr/lib/kura/kura-agent
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

# --- D2: terminal, containers, journal (ADR-027) ---

# upgrade <seconds> <path>: holds a WebSocket open and prints what came
upgrade() {
    curl -sk -i -N --http1.1 --max-time "$1" -b "${jar}" -H "Origin: ${base}" \
        -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
        -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' "${base}$2" | tr -d '\0' || true
}

# The terminal: systemd starts the shell as the signed-in user, in a unit of
# its own, and the unit goes when the browser does.
# terminal_units: the names of the terminals' units, one a line
terminal_units() { systemctl list-units --no-legend --plain 'kura-terminal-*.service' | awk '{print $1}'; }

# until_units <empty|open> <what>: waits up to 15 s for that state
until_units() {
    local want="$1" deadline=$((SECONDS + 15))
    while [ "$([ -n "$(terminal_units)" ] && echo open || echo empty)" != "${want}" ]; do
        if [ "${SECONDS}" -ge "${deadline}" ]; then
            # what systemd knows of them, for whoever reads this failure
            systemctl status --no-pager --lines=5 'kura-terminal-*.service' >&2 || true
            fail "$2"
        fi
        sleep 1
    done
}

upgrade 8 '/api/terminal?cols=100&rows=30' > "${out}/terminal.out" &
terminal=$!
until_units open "no kura-terminal unit while a terminal is open"
unit="$(terminal_units | head -1)"
[ "$(systemctl show -p User --value "${unit}")" = "${user}" ] || fail "${unit} does not run as ${user}"
shell_pid="$(systemctl show -p MainPID --value "${unit}")"
shell_user="$(ps -o user= -p "${shell_pid}" | tr -d ' ')"
[ "${shell_user}" = "${user}" ] || fail "the terminal's shell runs as ${shell_user:-nobody}, not ${user}"
[ "$(ps -o tty= -p "${shell_pid}" | tr -d ' ')" != '?' ] || fail "the terminal's shell has no terminal"
# only the terminal: the helper and desktopd are background jobs too
wait "${terminal}"
grep -q ' 101 ' "${out}/terminal.out" || fail "terminal WebSocket was not accepted"
# bash's prompt for this user, after the upgrade's own headers
grep -aq "${user}@" "${out}/terminal.out" || fail "the shell printed no prompt"
until_units empty "${unit} outlived its terminal"
upgrade 3 '/api/terminal?cols=0' | grep -q ' 400 ' || fail "a terminal of no width was not refused"

# Containers: what Docker has, through the helper
# --init: sh as PID 1 would ignore the stop signal and take Docker's whole grace time
docker run -d --init --name kura-e2e busybox sh -c 'echo kura-e2e-ready; sleep 600' >/dev/null
id="$(docker inspect -f '{{.Id}}' kura-e2e)"
listed() { curl -sk -b "${jar}" "${base}/api/containers" | jq -r --arg id "${id}" '.[] | select(.id == $id) | "\(.name) \(.state)"'; }
[ "$(listed)" = "kura-e2e running" ] || fail "the container is not listed as running: $(listed)"
status 403 -b "${jar}" -X POST "${base}/api/containers/${id}/stop"
status 204 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/containers/${id}/stop"
[ "$(listed)" = "kura-e2e exited" ] || fail "the container was not stopped: $(listed)"
status 204 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/containers/${id}/restart"
[ "$(listed)" = "kura-e2e running" ] || fail "the container was not restarted: $(listed)"
curl -sk -b "${jar}" "${base}/api/containers/${id}/logs?lines=5" | jq -e 'any(.[]; .text == "kura-e2e-ready")' >/dev/null ||
    fail "the container's logs are not read"
status 400 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/containers/kura-e2e/stop"
status 400 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/containers/${id}/kill"
status 404 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/containers/000000000000/stop"

# The journal, with journalctl's own arguments out of reach
curl -sk -b "${jar}" "${base}/api/journal?lines=5" | jq -e '(.entries | length) >= 1 and (.cursor | length) > 0' >/dev/null ||
    fail "the journal is not read"
status 400 -b "${jar}" "${base}/api/journal?unit=--file%3D%2Fetc%2Fshadow"
status 400 -b "${jar}" "${base}/api/journal?lines=100000"

# Updates: the status for everyone, a check as a job of its own (apt on the
# runner). Nothing is installed here, and the runner is not switched off:
# only the refusals of power are checked.
curl -sk -b "${jar}" "${base}/api/updates" | jq -e 'has("current") and has("available") and (.restartRequired | type == "boolean")' >/dev/null ||
    fail "the update status is not read"
status 403 -b "${jar}" -X POST "${base}/api/updates/check"
status 204 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/updates/check"
job_state() { curl -sk -b "${jar}" "${base}/api/updates" | jq -r '.job.state // "none"'; }
deadline=$((SECONDS + 120))
until [ "$(job_state)" = "done" ]; do
    [ "$(job_state)" != failed ] || fail "the update check failed: $(curl -sk -b "${jar}" "${base}/api/updates" | jq -c .job.output)"
    [ "${SECONDS}" -lt "${deadline}" ] || fail "the update check did not finish: $(job_state)"
    sleep 2
done
curl -sk -b "${jar}" "${base}/api/updates" | jq -e '.job.output | length > 0' >/dev/null || fail "the update check wrote nothing"
status 404 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/updates/downgrade"
status 404 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/power/hibernate"
status 403 -b "${jar}" -X POST "${base}/api/power/restart"

# Settings (ADR-029): read, and changed by the root command as a unit of its
# own. A person is added with a password (which crosses in a root-only
# file), signs in, changes their own password, and is removed. The clock's
# zone is set to the one it has. The host name and the network stay alone.
post_json() { status "$1" -b "$2" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}$3"; }
curl -sk -b "${jar}" "${base}/api/settings" | jq -e --arg u "${user}" \
    '(.hostname | length > 0) and (.time.zone | length > 0) and any(.users[]; .name == $u and .admin)' >/dev/null ||
    fail "the settings are not read"
zone="$(curl -sk -b "${jar}" "${base}/api/settings" | jq -r .time.zone)"
jq -nc --arg z "${zone}" '{what: "timezone", zone: $z}' | post_json 204 "${jar}" /api/settings
echo '{"what":"timezone","zone":"../../etc/passwd"}' | post_json 400 "${jar}" /api/settings
echo '{"what":"hostname","name":"a;reboot"}' | post_json 400 "${jar}" /api/settings
echo '{"what":"format-disk"}' | post_json 400 "${jar}" /api/settings
jq -nc --arg u "${user}" '{what: "user-remove", name: $u}' | post_json 400 "${jar}" /api/settings

new_pass="$(openssl rand -hex 12)"
jq -nc --arg p "${new_pass}" '{what: "user-add", name: "kura-e2e-new", password: $p, admin: false}' |
    post_json 204 "${jar}" /api/settings
id kura-e2e-new >/dev/null 2>&1 || fail "the new user was not made"
[ -z "$(sudo ls -A /run/kura-helper)" ] || fail "a password file was left in /run/kura-helper"
new_jar="$(mktemp)"
desktop_login_body kura-e2e-new "${new_pass}" |
    status 200 -c "${new_jar}" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
status 403 -b "${new_jar}" "${base}/api/settings"
own_pass="$(openssl rand -hex 12)"
jq -nc --arg c wrong --arg p "${own_pass}" '{current: $c, password: $p}' | post_json 400 "${new_jar}" /api/password
jq -nc --arg c "${new_pass}" --arg p "${own_pass}" '{current: $c, password: $p}' | post_json 204 "${new_jar}" /api/password
desktop_login_body kura-e2e-new "${own_pass}" | status 200 "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
desktop_login_body kura-e2e-new "${new_pass}" | status 401 "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
echo '{"what":"user-remove","name":"kura-e2e-new"}' | post_json 204 "${jar}" /api/settings
! id kura-e2e-new >/dev/null 2>&1 || fail "the new user was not removed"

# Files (ADR-031): done by an agent that systemd runs as the user, so the
# kernel decides. A folder is made, a file goes up and comes back the same,
# is owned by the user and not by root, goes to the trash and comes back;
# root's own folder stays shut.
home="$(curl -sk -b "${jar}" "${base}/api/files" | jq -r .home)"
[ "${home}" = "$(getent passwd "${user}" | cut -d: -f6)" ] || fail "Files does not start in the home folder: ${home}"
# The home folder is closed to the runner's own user, so the checks on what
# is in it are made as root.
# A name of this run's own, so an earlier run that failed leaves nothing in
# the way (in the folder or in the trash); cleanup removes the folder.
work="${home}/kura-e2e-files-$$"
files_op() { status "$1" -b "${jar}" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/files"; }
jq -nc --arg p "${work}" '{op: "make-dir", path: $p}' | files_op 204
head -c 700000 /dev/urandom > "${out}/sent-$$.bin"
status 204 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X PUT --data-binary "@${out}/sent-$$.bin" \
    -H 'content-type: application/octet-stream' "${base}/api/files/content?path=${work}/sent-$$.bin"
[ "$(sudo stat -c '%U' "${work}/sent-$$.bin")" = "${user}" ] || fail "the uploaded file is not the user's own"
curl -sk -b "${jar}" -o "${out}/back.bin" "${base}/api/files/content?path=${work}/sent-$$.bin"
cmp -s "${out}/sent-$$.bin" "${out}/back.bin" || fail "the file did not come back as it went up"
status 409 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X PUT --data-binary "@${out}/sent-$$.bin" "${base}/api/files/content?path=${work}/sent-$$.bin"
jq -nc --arg p "${work}/sent-$$.bin" '{op: "trash", path: $p}' | files_op 204
! sudo test -e "${work}/sent-$$.bin" || fail "the file was not moved to the trash"
curl -sk -b "${jar}" "${base}/api/files/trash" | jq -e --arg p "${work}/sent-$$.bin" 'any(.items[]; .path == $p)' >/dev/null ||
    fail "the trash does not list the file"
jq -nc --arg n "sent-$$.bin" '{op: "restore", name: $n}' | files_op 204
sudo test -f "${work}/sent-$$.bin" || fail "the file was not put back"
jq -nc --arg p "${work}" '{op: "delete", path: $p}' | files_op 204
! sudo test -e "${work}" || fail "the folder was not deleted"
status 403 -b "${jar}" "${base}/api/files?path=/root"
status 400 -b "${jar}" "${base}/api/files?path=/home/../root"
echo '{"op":"read","path":"/etc/shadow","offset":0}' | files_op 400
echo '{"op":"write","path":"/tmp/x","id":"a","offset":0,"last":true}' | files_op 400
status 403 -b "${jar}" "${base}/api/files/content?path=/etc/shadow"
status 403 -b "${jar}" -X PUT --data-binary x "${base}/api/files/content?path=${home}/kura-e2e-forged"
[ -n "$(systemctl list-units --no-legend 'kura-files-*')" ] || fail "no file agent runs as a unit of its own"

# The App Catalog (ADR-032): what Kura ships is listed, and only that, on a
# port of the administrator's choosing, can be asked for. Nothing is
# installed here: that would pull an image on every run.
curl -sk -b "${jar}" "${base}/api/catalog" | jq -e '(.apps | length >= 6) and any(.apps[]; .id == "jellyfin" and .installed == null)' >/dev/null ||
    fail "the catalog is not read"
catalog_op() { status "$1" -b "${jar}" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/catalog"; }
echo '{"what":"install","id":"nextcloud","port":8080}' | catalog_op 400
echo '{"what":"install","id":"jellyfin","port":22}' | catalog_op 400
echo '{"what":"install","id":"jellyfin","port":8096,"image":"evil"}' | catalog_op 400
echo '{"what":"update","id":"jellyfin"}' | catalog_op 400
echo '{"what":"install","id":"jellyfin","port":8096}' | status 403 -b "${jar}" "${DESKTOP_POST[@]}" "${base}/api/catalog"
[ ! -e /srv/apps/jellyfin ] || fail "a refused request left something in /srv/apps"

# A user who is not an administrator: their own shell and the list, nothing else
if [ -n "${guest}" ]; then
    guest_jar="$(mktemp)"
    desktop_login_body "${guest}" "${password}" |
        status 200 -c "${guest_jar}" "${DESKTOP_CHANGE[@]}" "${DESKTOP_POST[@]}" "${base}/api/login"
    status 200 -b "${guest_jar}" "${base}/api/containers"
    status 403 -b "${guest_jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/containers/${id}/stop"
    status 403 -b "${guest_jar}" "${base}/api/containers/${id}/logs"
    status 403 -b "${guest_jar}" "${base}/api/journal"
    status 200 -b "${guest_jar}" "${base}/api/updates"
    status 403 -b "${guest_jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/updates/install"
    status 403 -b "${guest_jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/power/restart"
    status 403 -b "${guest_jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/power/shutdown"
    status 403 -b "${guest_jar}" "${base}/api/settings"
    status 403 -b "${guest_jar}" "${base}/api/catalog"
    echo '{"what":"ntp","on":false}' | post_json 403 "${guest_jar}" /api/settings
    [ "$(listed)" = "kura-e2e running" ] || fail "a user who is not an administrator stopped the container"
fi

# Signing out ends the helper's ticket with the session, and the file agent
status 204 -b "${jar}" "${DESKTOP_CHANGE[@]}" -X POST "${base}/api/logout"
status 401 -b "${jar}" "${base}/api/containers"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$(systemctl list-units --no-legend 'kura-files-*')" ] || break
    sleep 0.5
done
[ -z "$(systemctl list-units --no-legend 'kura-files-*')" ] || fail "a file agent outlived its session"

rss_kb="$(ps -o rss= -p "${desktopd}" | tr -d ' ')"
echo "kura-desktopd RSS: ${rss_kb} kB"
[ "${rss_kb}" -lt "${DESKTOP_RSS_MAX_KIB}" ] || fail "kura-desktopd uses ${rss_kb} kB, over the 40 MB budget"
echo "end-to-end: ok"
