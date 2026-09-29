#!/usr/bin/env bats
# tests/shell/install-tomo.bats — tests for scripts/common/install-tomo.sh
# (installs the Tomo .deb into the image rootfs from inside a chroot)
#
# chroot needs root, so a stub records each call and emulates what the real
# commands would leave behind in the rootfs.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/install-tomo.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    CALLS="${BATS_TEST_TMPDIR}/chroot-calls"
    mkdir -p "${ROOTFS}/usr/bin" "${ROOTFS}/tmp"
    echo "real systemctl" > "${ROOTFS}/usr/bin/systemctl"
    DEB="${BATS_TEST_TMPDIR}/tomo_0.0.76_arm64.deb"
    echo "deb" > "${DEB}"
    APT_EXIT=0
    export ROOTFS CALLS APT_EXIT
}

# chroot <rootfs> <cmd...>: log the command, emulate its effect on the rootfs.
chroot() {
    local root="$1"; shift
    echo "$*" >> "${CALLS}"
    case "$1" in
        dpkg-divert)
            if [[ " $* " == *" --add "* ]]; then
                mv "${root}/usr/bin/systemctl" "${root}/usr/bin/systemctl.kura-real"
            else
                rm -f "${root}/usr/bin/systemctl"
                mv "${root}/usr/bin/systemctl.kura-real" "${root}/usr/bin/systemctl"
            fi
            ;;
        apt-get)
            # While installing, systemctl must be the no-op stub
            grep -q "exit 0" "${root}/usr/bin/systemctl" || return 99
            [ "${APT_EXIT}" -eq 0 ] || return "${APT_EXIT}"
            mkdir -p "${root}/opt/tomo/data/secrets" "${root}/etc/systemd/system"
            echo "baked-secret" > "${root}/opt/tomo/data/secrets/jwt"
            echo "[Unit]" > "${root}/etc/systemd/system/tomod.service"
            ;;
    esac
}

# ---- install_tomo ----

@test "install_tomo: diverts systemctl, installs the deb, restores systemctl" {
    run install_tomo "${ROOTFS}" "${DEB}"
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "${CALLS}")" = \
      "dpkg-divert --local --rename --divert /usr/bin/systemctl.kura-real --add /usr/bin/systemctl" ]
    [[ "$(sed -n 2p "${CALLS}")" == "apt-get install -y -qq --no-install-recommends /tmp/tomo.deb" ]]
    [[ "$(sed -n 3p "${CALLS}")" == *"--remove /usr/bin/systemctl" ]]
    [ "$(cat "${ROOTFS}/usr/bin/systemctl")" = "real systemctl" ]
}

@test "install_tomo: enables tomod at boot" {
    run install_tomo "${ROOTFS}" "${DEB}"
    [ "$status" -eq 0 ]
    [ "$(readlink "${ROOTFS}/etc/systemd/system/multi-user.target.wants/tomod.service")" = \
      "/etc/systemd/system/tomod.service" ]
}

@test "install_tomo: removes the JWT secret baked in by the package" {
    run install_tomo "${ROOTFS}" "${DEB}"
    [ "$status" -eq 0 ]
    [ ! -e "${ROOTFS}/opt/tomo/data/secrets/jwt" ]
}

@test "install_tomo: removes the copied package from the rootfs" {
    run install_tomo "${ROOTFS}" "${DEB}"
    [ "$status" -eq 0 ]
    [ ! -e "${ROOTFS}/tmp/tomo.deb" ]
}

@test "install_tomo: restores systemctl and fails when apt fails" {
    APT_EXIT=100
    run install_tomo "${ROOTFS}" "${DEB}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to install Tomo"* ]]
    [ "$(cat "${ROOTFS}/usr/bin/systemctl")" = "real systemctl" ]
    [ ! -e "${ROOTFS}/tmp/tomo.deb" ]
}

@test "install_tomo: fails when the package does not install its unit" {
    # shellcheck disable=SC2329  # replaces the stub for this test
    chroot() {
        local root="$1"; shift
        case "$1" in
            dpkg-divert)
                if [[ " $* " == *" --add "* ]]; then
                    mv "${root}/usr/bin/systemctl" "${root}/usr/bin/systemctl.kura-real"
                else
                    rm -f "${root}/usr/bin/systemctl"
                    mv "${root}/usr/bin/systemctl.kura-real" "${root}/usr/bin/systemctl"
                fi
                ;;
        esac
    }
    run install_tomo "${ROOTFS}" "${DEB}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"tomod.service"* ]]
}

@test "install_tomo: fails for a missing package" {
    run install_tomo "${ROOTFS}" "${BATS_TEST_TMPDIR}/missing.deb"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    [ ! -s "${CALLS}" ]
}

# ---- tomo_traefik_image ----

@test "tomo_traefik_image: reads the version Tomo pins in its code" {
    mkdir -p "${ROOTFS}/opt/tomo/dist"
    printf 'const TRAEFIK_VERSION = "v3.3";\nconst TRAEFIK_IMAGE = `traefik:${TRAEFIK_VERSION}`;\n' \
        > "${ROOTFS}/opt/tomo/dist/traefik-proxy.js"
    run tomo_traefik_image "${ROOTFS}"
    [ "$status" -eq 0 ]
    [ "$output" = "traefik:v3.3" ]
}

@test "tomo_traefik_image: fails when Tomo's code is missing" {
    run tomo_traefik_image "${ROOTFS}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"traefik-proxy.js"* ]]
}

@test "tomo_traefik_image: fails when the version pattern changed" {
    mkdir -p "${ROOTFS}/opt/tomo/dist"
    echo 'const IMAGE = "traefik:latest";' > "${ROOTFS}/opt/tomo/dist/traefik-proxy.js"
    run tomo_traefik_image "${ROOTFS}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"TRAEFIK_VERSION"* ]]
}
