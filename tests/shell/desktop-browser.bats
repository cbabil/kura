#!/usr/bin/env bats
# tests/shell/desktop-browser.bats — the Browser (ADR-036): each person's
# own Debian Chromium in TigerVNC's X server, run as them by the helper,
# shown in Kura Desktop. Its packages come with OS_BROWSER on the PC image
# only; its command is on every PC. (The unit's settings are the helper's:
# kura-helper/src/browser/systemd.rs.)

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    desktop_rootfs
    BROWSER=$(branded browser)
    BIN="${BATS_TEST_TMPDIR}/bin"
    LOG="${BATS_TEST_TMPDIR}/calls"
    mkdir -p "${BIN}"
    export RUNTIME_DIRECTORY="${BATS_TEST_TMPDIR}/run" HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${RUNTIME_DIRECTORY}" "${HOME}"
}

# stub <name> <body>: a program in BIN that notes its arguments, then runs body
stub() {
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "${LOG}" "$2" > "${BIN}/$1"
    chmod +x "${BIN}/$1"
}

# the X server stand-in makes its socket and waits to be stopped
x_server() {
    # shellcheck disable=SC2016
    stub Xtigervnc 'for a in "$@"; do [ "${prev:-}" = "-rfbunixpath" ] && : > "$a"; prev="$a"; done; sleep 30 & wait'
}

@test "the Pi's image has nothing of the Browser" {
    run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ ! -e "${ROOTFS}/usr/lib/kura/kura-browser" ]
}

@test "every PC image has the command, and no unit or account of its own" {
    OS_KIOSK_FILES=true run "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    [ "$status" -eq 0 ]
    [ -x "${ROOTFS}/usr/lib/kura/kura-browser" ]
    # each person's browser is a unit the helper starts, as them
    [ ! -e "${ROOTFS}/usr/lib/systemd/system/kura-browser.service" ]
    [ ! -e "${ROOTFS}/usr/lib/sysusers.d/kura-browser.conf" ]
    run grep -l "__BRAND" "${ROOTFS}/usr/lib/kura/kura-browser"
    [ -z "$output" ]
}

@test "the kura package owns the command, so an upgrade keeps it" {
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    OS_KIOSK_FILES=true "${INSTALL}" "${ROOTFS}" "${REPO_ROOT}/packages" "${DIST}"
    run kura_owned "${ROOTFS}" kura
    [[ "$output" == *"usr/lib/kura/kura-browser"* ]]
}

@test "the build adds the Browser's packages to a PC image built with OS_BROWSER only" {
    # shellcheck disable=SC2016
    grep -qF 'if [ "${OS_BROWSER:-false}" = "true" ] && [ "${TARGET}" = "x86_64" ]; then' "${REPO_ROOT}/build.sh"
    file_has "${REPO_ROOT}/build.sh" 'packages-browser.list'
    grep -q '^OS_BROWSER="false"' "${REPO_ROOT}/.env.example"
    local package
    for package in chromium tigervnc-standalone-server xauth matchbox-window-manager; do
        grep -qx "${package}" "${REPO_ROOT}/config/packages-browser.list" || { echo "missing: ${package}"; return 1; }
        run grep -x "${package}" "${REPO_ROOT}/config/packages-common.list" "${REPO_ROOT}/config/packages-rpi5.list" "${REPO_ROOT}/config/packages-x86_64.list"
        [ "$status" -ne 0 ]
    done
}

@test "run: X listens on a unix socket only, with a cookie, and Chromium keeps its sandbox" {
    x_server
    stub xauth ""
    stub matchbox-window-manager 'sleep 30 & wait'
    stub chromium "sleep 0.5"
    run env BROWSER_BIN="${BIN}" "${BROWSER}" run
    [ "$status" -eq 0 ]
    local x
    x=$(grep '^Xtigervnc ' "${LOG}")
    for want in ":$(id -u)" "-auth ${RUNTIME_DIRECTORY}/Xauthority" "-nolisten tcp" "-rfbport -1" \
                "-rfbunixpath ${RUNTIME_DIRECTORY}/vnc.sock" "-rfbunixmode 0660" "-SecurityTypes None" \
                "-MaxDisconnectionTime 900" "-nopn"; do
        [[ "${x}" == *" ${want}"* ]] || { echo "X lacks: ${want}"; return 1; }
    done
    [[ "${x}" != *"-localhost"* && "${x}" != *"-rfbport 59"* ]]
    # a fresh cookie of 32 hex digits, for the display of the person's uid
    grep -qE "^xauth -f ${RUNTIME_DIRECTORY}/Xauthority add :$(id -u) \. [0-9a-f]{32}$" "${LOG}"
    grep -qx "matchbox-window-manager -use_titlebar no" "${LOG}"
    local c
    c=$(grep '^chromium ' "${LOG}")
    # the profile in the person's home
    for want in "--user-data-dir=${HOME}/.config/chromium" "--ozone-platform=x11" "--no-first-run" \
                "--password-store=basic" "--start-maximized"; do
        [[ "${c}" == *" ${want}"* ]] || { echo "chromium lacks: ${want}"; return 1; }
    done
    [[ "${c}" != *"--no-sandbox"* && "${c}" != *"--remote-debugging"* ]]
}

@test "run: Chromium's end ends the X server, and an X server that never listens is an error" {
    x_server
    stub xauth ""
    stub matchbox-window-manager 'sleep 30 & wait'
    stub chromium ""
    run env BROWSER_BIN="${BIN}" "${BROWSER}" run
    [ "$status" -eq 0 ]
    # nothing of the stand-ins is left running
    run pgrep -f "${BIN}/Xtigervnc"
    [ "$status" -ne 0 ]
    stub Xtigervnc 'exit 1'
    run env BROWSER_BIN="${BIN}" BROWSER_WAIT=1 "${BROWSER}" run
    [ "$status" -ne 0 ]
    [ "$(grep -c '^chromium' "${LOG}")" -eq 1 ]   # the second run never started it
}

@test "run: a stop closes Chromium first, so it keeps its session" {
    x_server
    stub xauth ""
    stub matchbox-window-manager 'sleep 30 & wait'
    # shellcheck disable=SC2016
    stub chromium "trap 'echo \"chromium closed\" >> \"${LOG}\"; exit 0' TERM; sleep 30 & wait"
    BROWSER_BIN="${BIN}" "${BROWSER}" run &
    local pid=$! tries=50
    until grep -q '^chromium ' "${LOG}" 2>/dev/null || [ "${tries}" -eq 0 ]; do sleep 0.1; tries=$((tries - 1)); done
    sleep 0.2
    kill -TERM "${pid}"
    wait "${pid}"
    grep -qx "chromium closed" "${LOG}"
    run pgrep -f "${BIN}/Xtigervnc"
    [ "$status" -ne 0 ]
}

@test "nothing else is a command, and it runs only under its unit" {
    run "${BROWSER}" https://example.org
    [ "$status" -eq 2 ]
    RUNTIME_DIRECTORY="" run "${BROWSER}" run
    [ "$status" -ne 0 ]
    run "${BROWSER}"
    [ "$status" -eq 2 ]
}
