#!/usr/bin/env bats
# tests/shell/desktop-apps.bats — the App Catalog (ADR-032): the templates in
# packages/os-desktop/catalog/ and packages/os-desktop/src/os-apps, the root
# command that installs them.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
CATALOG="${REPO_ROOT}/packages/os-desktop/catalog"

setup() {
    load test_helper
    ROOT="${BATS_TEST_TMPDIR}/root"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    mkdir -p "${ROOT}/usr/lib/kura" "${ROOT}/etc" "${ROOT}/srv"
    cp -R "${CATALOG}" "${ROOT}/usr/lib/kura/catalog"
    echo "Europe/Paris" > "${ROOT}/etc/timezone"
    touch "${CALLS}"
    local tmp="${BATS_TEST_TMPDIR}/apps.sh"
    sed -e 's|__BRAND__|kura|g' -e '/^set -euo pipefail$/d' -e '/^main "\$@"$/d' \
        "${REPO_ROOT}/packages/os-desktop/src/os-apps" > "${tmp}"
    # shellcheck disable=SC1090
    APPS_ROOT="${ROOT}" source "${tmp}"
    ADMIN_GROUP="$(id -gn)"   # a group the test may give folders to
    BUSY=""                   # ports something listens on
    FAIL=""                   # a docker compose step that fails
    # ss -Hltnu "sport = :<port>": a line when the port is one of BUSY
    ss() {
        local asked="${*: -1}"
        case " ${BUSY} " in *" ${asked##*:} "*) echo "LISTEN" ;; esac
    }
    docker() {
        log_call docker "$@"
        [ -z "${FAIL}" ] || case "$*" in *"${FAIL}"*) return 1 ;; esac
    }
}

env_of() { cat "${ROOT}/srv/apps/$1/.env"; }

# ---- the templates ----

@test "templates: each has a compose file and its facts, under its own name" {
    local dir id
    for dir in "${CATALOG}"/*/; do
        id="$(basename "${dir}")"
        [[ "${id}" =~ ^[a-z][a-z0-9-]{1,30}$ ]]
        [ "$(jq -r .id "${dir}app.json")" = "${id}" ]
        jq -e '(.name | length > 0) and (.version | test("^[0-9][0-9.]*$")) and (.port >= 1024) and (.port <= 65535)
               and (.fixedPorts | type == "array") and (.shared | type == "array") and (.homepage | startswith("https://"))' \
            "${dir}app.json" >/dev/null || { echo "bad facts: ${id}"; return 1; }
        grep -qx "  ${id}:" "${dir}compose.yaml"
        grep -qx "    container_name: kura-${id}" "${dir}compose.yaml"
    done
    [ "$(find "${CATALOG}" -mindepth 1 -maxdepth 1 -type d | wc -l)" -ge 6 ]
}

@test "templates: no two apps ask for the same port" {
    local ports
    ports="$(jq -r '.port, .fixedPorts[]' "${CATALOG}"/*/app.json | sort)"
    [ -z "$(uniq -d <<< "${ports}")" ]
}

@test "templates: images are pinned, and the version shown is the image's" {
    local file image version
    for file in "${CATALOG}"/*/compose.yaml; do
        [ "$(grep -c '^    image: ' "${file}")" -eq 1 ]
        image="$(sed -n 's/^    image: //p' "${file}")"
        [[ "${image}" =~ ^[a-z0-9./-]+:v?[0-9][0-9.]*$ ]] || { echo "not pinned: ${image}"; return 1; }
        version="$(jq -r .version "$(dirname "${file}")/app.json")"
        [ "${image##*:}" = "${version}" ] || [ "${image##*:}" = "v${version}" ]
    done
}

@test "templates: nothing gives a container the host" {
    local file
    for file in "${CATALOG}"/*/compose.yaml; do
        run grep -nE 'privileged|network_mode|pid:|ipc:|cap_add|devices:|docker\.sock|/var/run|/proc|/sys|/dev|userns_mode|security_opt: *\[' "${file}"
        [ "$status" -ne 0 ] || { echo "${file}: ${output}"; return 1; }
        grep -qx '      - no-new-privileges:true' "${file}"
        grep -qx '    restart: unless-stopped' "${file}"
    done
}

@test "templates: only the app's own data folder is mounted, and the chosen port is the one published" {
    local file line fixed
    for file in "${CATALOG}"/*/compose.yaml; do
        while IFS= read -r line; do
            [[ "${line}" =~ ^\$\{KURA_DATA\}/[a-z]+:/[a-z/]+(:ro)?$ ]] || { echo "${file}: mount ${line}"; return 1; }
        done < <(sed -n '/^    volumes:/,$ s/^      - //p' "${file}")
        [ "$(grep -c '"${KURA_PORT}:' "${file}")" -eq 1 ]
        fixed="$(jq -r '[.fixedPorts[] | tostring] | join(" ")' "$(dirname "${file}")/app.json")"
        while IFS= read -r line; do
            case " ${fixed} " in *" ${line} "*) ;; *) echo "${file}: port ${line} is not in its facts"; return 1 ;; esac
        done < <(sed -n 's/^      - "\([0-9]*\):.*/\1/p' "${file}")
    done
}

# ---- install ----

@test "install: the template, the port and the data folder, then the app is started" {
    run main install jellyfin 8096
    [ "$status" -eq 0 ]
    cmp "${CATALOG}/jellyfin/compose.yaml" "${ROOT}/srv/apps/jellyfin/compose.yaml"
    [ "$(env_of jellyfin)" = "$(printf 'KURA_PORT=8096\nKURA_DATA=/srv/apps/jellyfin/data\nKURA_TZ=Europe/Paris\nKURA_VERSION=10.10.7')" ]
    [ -d "${ROOT}/srv/apps/jellyfin/data/media" ]
    grep -q "docker compose --project-name kura-jellyfin --project-directory ${ROOT}/srv/apps/jellyfin .* pull" "${CALLS}"
    grep -q "docker compose --project-name kura-jellyfin .* up --detach" "${CALLS}"
}

@test "install: refuses what is not in the catalog, a bad port, a port in use, a second time" {
    local bad
    for bad in "../etc 8080" "Jellyfin 8096" "nextcloud 8080" "jellyfin 80" "jellyfin 70000" "jellyfin 80a0" "jellyfin" "jellyfin 8096;id"; do
        # shellcheck disable=SC2086
        run main install ${bad}
        [ "$status" -ne 0 ] || { echo "accepted: ${bad}"; return 1; }
    done
    [ ! -s "${CALLS}" ]
    [ ! -e "${ROOT}/srv/apps" ]
    BUSY="8096"
    run main install jellyfin 8096
    [ "$status" -ne 0 ]
    [[ "$output" == *"port 8096 is in use"* ]]
    BUSY="53"
    run main install adguard-home 3000
    [ "$status" -ne 0 ]
    [[ "$output" == *"port 53, which this app needs, is in use"* ]]
    BUSY=""
    run main install jellyfin 8096
    [ "$status" -eq 0 ]
    run main install jellyfin 8097
    [ "$status" -ne 0 ]
    [[ "$output" == *"already installed"* ]]
}

@test "install: an app that does not start is not left half-installed" {
    FAIL="up --detach"
    run main install gitea 3003
    [ "$status" -ne 0 ]
    grep -q "down --remove-orphans" "${CALLS}"
    [ ! -e "${ROOT}/srv/apps/gitea/.env" ]
    [ ! -e "${ROOT}/srv/apps/gitea/compose.yaml" ]
}

# ---- update and remove ----

@test "update: takes the catalog's template again and keeps the port" {
    main install gitea 3999
    echo "# older" > "${ROOT}/srv/apps/gitea/compose.yaml"
    sed -i.bak 's/^KURA_VERSION=.*/KURA_VERSION=1.0.0/' "${ROOT}/srv/apps/gitea/.env"
    : > "${CALLS}"
    run main update gitea
    [ "$status" -eq 0 ]
    cmp "${CATALOG}/gitea/compose.yaml" "${ROOT}/srv/apps/gitea/compose.yaml"
    env_of gitea | grep -qx "KURA_PORT=3999"
    env_of gitea | grep -qx "KURA_VERSION=1.23.1"
    grep -q " pull" "${CALLS}"
    grep -q "up --detach" "${CALLS}"
    run main update jellyfin
    [ "$status" -ne 0 ]
    [[ "$output" == *"not installed"* ]]
}

@test "update: one that fails leaves the app as it was, version included" {
    main install gitea 3999
    echo "# older" > "${ROOT}/srv/apps/gitea/compose.yaml"
    sed -i.bak 's/^KURA_VERSION=.*/KURA_VERSION=1.0.0/' "${ROOT}/srv/apps/gitea/.env"
    FAIL=" pull"
    run main update gitea
    [ "$status" -ne 0 ]
    [ "$(cat "${ROOT}/srv/apps/gitea/compose.yaml")" = "# older" ]
    env_of gitea | grep -qx "KURA_VERSION=1.0.0"
    [ -z "$(find "${ROOT}/srv/apps/gitea" -name '*.before')" ]
}

@test "install: what an app keeps is for root and the administrators only" {
    main install jellyfin 8096
    [ "$(stat -f '%Lp' "${ROOT}/srv/apps/jellyfin/data" 2>/dev/null || stat -c '%a' "${ROOT}/srv/apps/jellyfin/data")" = "750" ]
}

@test "install: a folder of that name that is not Kura's is left alone" {
    mkdir -p "${ROOT}/srv/apps/gitea"
    echo "services: {}" > "${ROOT}/srv/apps/gitea/compose.yaml"
    run main install gitea 3003
    [ "$status" -ne 0 ]
    [ "$(cat "${ROOT}/srv/apps/gitea/compose.yaml")" = "services: {}" ]
    # ...and a .env that is not Kura's does not count as installed
    echo "SOMETHING=else" > "${ROOT}/srv/apps/gitea/.env"
    run main update gitea
    [ "$status" -ne 0 ]
    run main remove gitea
    [ "$status" -ne 0 ]
    [ -f "${ROOT}/srv/apps/gitea/compose.yaml" ]
}

@test "install: the chosen port is not one the app needs for something else, and a strange time zone is not passed on" {
    run main install adguard-home 53
    [ "$status" -ne 0 ]
    run main install syncthing 22000
    [ "$status" -ne 0 ]
    printf 'Europe/Paris $(id)\nKURA_PORT=1\n' > "${ROOT}/etc/timezone"
    main install gitea 3003
    env_of gitea | grep -qx "KURA_TZ=UTC"
    [ "$(grep -c KURA_PORT "${ROOT}/srv/apps/gitea/.env")" -eq 1 ]
}

@test "remove: an app the catalog no longer has can still be removed" {
    main install gitea 3003
    mv "${ROOT}/usr/lib/kura/catalog/gitea" "${ROOT}/usr/lib/kura/catalog-gone"
    run main remove gitea
    [ "$status" -eq 0 ]
    [ ! -e "${ROOT}/srv/apps/gitea/.env" ]
}

@test "remove: stops the app and keeps its data unless asked" {
    main install gitea 3003
    touch "${ROOT}/srv/apps/gitea/data/repo"
    run main remove gitea
    [ "$status" -eq 0 ]
    grep -q "down --remove-orphans" "${CALLS}"
    [ -f "${ROOT}/srv/apps/gitea/data/repo" ]
    [ ! -e "${ROOT}/srv/apps/gitea/.env" ]
    run main remove gitea
    [ "$status" -ne 0 ]
    main install gitea 3003
    run main remove gitea everything
    [ "$status" -ne 0 ]
    run main remove gitea data
    [ "$status" -eq 0 ]
    [ ! -e "${ROOT}/srv/apps/gitea" ]
}

@test "anything else is refused" {
    run main start jellyfin
    [ "$status" -ne 0 ]
    run main
    [ "$status" -ne 0 ]
}
