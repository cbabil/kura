#!/usr/bin/env bats
# tests/shell/docker-repo.bats — tests for scripts/common/docker-repo.sh
# (build-time Docker APT repo setup used by the RPi5 target)

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# Plain-command assertions: bash 3.2 (macOS) ignores a failing [[ ]] that is
# not the last command in a test, so pattern checks go through functions.
output_has() { [[ "$output" == *"$1"* ]]; }
matches() { [[ "$1" == $2 ]]; }

# Generate one throwaway signing key for the whole file (keygen is slow).
setup_file() {
    export TEST_GNUPGHOME="${BATS_FILE_TMPDIR}/gnupg"
    mkdir -p "${TEST_GNUPGHOME}"
    chmod 700 "${TEST_GNUPGHOME}"
    GNUPGHOME="${TEST_GNUPGHOME}" gpg --batch --passphrase '' \
        --quick-gen-key "Kura Test Signing Key" ed25519 sign never 2>/dev/null
    GNUPGHOME="${TEST_GNUPGHOME}" gpg --batch --armor --export \
        > "${BATS_FILE_TMPDIR}/test-key.asc"
    TEST_KEY_FPR=$(GNUPGHOME="${TEST_GNUPGHOME}" gpg --batch --with-colons \
        --list-keys | awk -F: '/^fpr:/{print $10; exit}')
    export TEST_KEY_FPR
}

setup() {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/docker-repo.sh"
    TEST_KEY="${BATS_FILE_TMPDIR}/test-key.asc"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}/etc"
    printf 'ID=debian\nVERSION_CODENAME=trixie\n' > "${ROOTFS}/etc/os-release"
}

# key_records <file>: gpg colon listing of the keys in an armored file.
key_records() {
    local home
    home=$(mktemp -d /tmp/kgpg.XXXXXX)
    GNUPGHOME="${home}" gpg --batch --show-keys --with-colons "$1" 2>/dev/null
    rm -rf "${home}"
}

# Stub curl: "download" the test key to the -o destination.
stub_curl_ok() {
    curl() {
        local out=""
        while [ $# -gt 0 ]; do
            [ "$1" = "-o" ] && out="$2"
            shift
        done
        cp "${TEST_KEY}" "${out}"
    }
}

# ---- docker_key_fingerprint / verify_docker_key ----

@test "docker_key_fingerprint: reads fingerprint from armored key" {
    run docker_key_fingerprint "${TEST_KEY}"
    [ "$status" -eq 0 ]
    [ "$output" = "${TEST_KEY_FPR}" ]
}

@test "docker_key_fingerprint: empty for non-key file" {
    echo "not a key" > "${BATS_TEST_TMPDIR}/junk"
    run docker_key_fingerprint "${BATS_TEST_TMPDIR}/junk"
    [ -z "$output" ]
}

@test "verify_docker_key: accepts key matching the pin" {
    DOCKER_GPG_FINGERPRINT="${TEST_KEY_FPR}"
    run verify_docker_key "${TEST_KEY}"
    [ "$status" -eq 0 ]
}

@test "verify_docker_key: rejects key not matching the pin" {
    run verify_docker_key "${TEST_KEY}"
    [ "$status" -eq 1 ]
    output_has "fingerprint mismatch"
}

@test "verify_docker_key: rejects unreadable key" {
    echo "garbage" > "${BATS_TEST_TMPDIR}/junk"
    run verify_docker_key "${BATS_TEST_TMPDIR}/junk"
    [ "$status" -eq 1 ]
    output_has "could not read"
}

# ---- rootfs_codename ----

@test "rootfs_codename: reads unquoted codename" {
    run rootfs_codename "${ROOTFS}"
    [ "$output" = "trixie" ]
}

@test "rootfs_codename: strips quotes" {
    printf 'VERSION_CODENAME="bookworm"\n' > "${ROOTFS}/etc/os-release"
    run rootfs_codename "${ROOTFS}"
    [ "$output" = "bookworm" ]
}

@test "rootfs_codename: falls back to usr/lib/os-release" {
    rm "${ROOTFS}/etc/os-release"
    mkdir -p "${ROOTFS}/usr/lib"
    printf 'VERSION_CODENAME=trixie\n' > "${ROOTFS}/usr/lib/os-release"
    run rootfs_codename "${ROOTFS}"
    [ "$output" = "trixie" ]
}

@test "rootfs_codename: fails when os-release is missing" {
    rm "${ROOTFS}/etc/os-release"
    run rootfs_codename "${ROOTFS}"
    [ "$status" -ne 0 ]
}

# ---- docker_apt_source_line ----

@test "docker_apt_source_line: arm64 trixie" {
    run docker_apt_source_line arm64 trixie
    [ "$output" = "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" ]
}

# ---- install_docker_repo ----

@test "install_docker_repo: installs keyring and source list" {
    DOCKER_GPG_FINGERPRINT="${TEST_KEY_FPR}"
    stub_curl_ok
    run install_docker_repo "${ROOTFS}" arm64
    [ "$status" -eq 0 ]
    [ -s "${ROOTFS}/etc/apt/keyrings/docker.asc" ]
    grep -q "arch=arm64 .* trixie stable" "${ROOTFS}/etc/apt/sources.list.d/docker.list"
}

@test "install_docker_repo: installs only the pinned key, not extra keys in the download" {
    # A second key appended to the download must not become trusted by apt
    local extra_home   # short path: gpg-agent socket paths are length-limited
    extra_home=$(mktemp -d /tmp/kgpg.XXXXXX)
    GNUPGHOME="${extra_home}" gpg --batch --passphrase '' \
        --quick-gen-key "Attacker Key" ed25519 sign never 2>/dev/null
    cat "${TEST_KEY}" > "${BATS_TEST_TMPDIR}/bundle.asc"
    GNUPGHOME="${extra_home}" gpg --batch --armor --export >> "${BATS_TEST_TMPDIR}/bundle.asc"
    TEST_KEY="${BATS_TEST_TMPDIR}/bundle.asc"
    DOCKER_GPG_FINGERPRINT="${TEST_KEY_FPR}"
    stub_curl_ok
    run install_docker_repo "${ROOTFS}" arm64
    [ "$status" -eq 0 ]
    local installed="${ROOTFS}/etc/apt/keyrings/docker.asc"
    [ "$(key_records "${installed}" | grep -c '^pub:')" = "1" ]
    [ "$(key_records "${installed}" | awk -F: '/^fpr:/{print $10; exit}')" = "${TEST_KEY_FPR}" ]
    rm -rf "${extra_home}"
}

@test "install_docker_repo: refuses key with wrong fingerprint" {
    stub_curl_ok
    run install_docker_repo "${ROOTFS}" arm64
    [ "$status" -eq 1 ]
    [ ! -e "${ROOTFS}/etc/apt/keyrings/docker.asc" ]
    [ ! -e "${ROOTFS}/etc/apt/sources.list.d/docker.list" ]
}

@test "install_docker_repo: fails when download fails" {
    # shellcheck disable=SC2329  # invoked by install_docker_repo
    curl() { return 22; }
    run install_docker_repo "${ROOTFS}" arm64
    [ "$status" -eq 1 ]
    output_has "failed to download"
    [ ! -e "${ROOTFS}/etc/apt/sources.list.d/docker.list" ]
}

@test "install_docker_repo: fails without codename" {
    printf 'ID=debian\n' > "${ROOTFS}/etc/os-release"
    stub_curl_ok
    run install_docker_repo "${ROOTFS}" arm64
    [ "$status" -eq 1 ]
    output_has "codename"
}

# ---- enable_docker_units ----

@test "enable_docker_units: enables docker and containerd at boot" {
    run enable_docker_units "${ROOTFS}"
    [ "$status" -eq 0 ]
    local wants="${ROOTFS}/etc/systemd/system/multi-user.target.wants"
    [ "$(readlink "${wants}/docker.service")" = "/usr/lib/systemd/system/docker.service" ]
    [ "$(readlink "${wants}/containerd.service")" = "/usr/lib/systemd/system/containerd.service" ]
}

# ---- build wiring (Docker is baked into every target) ----

@test "packages-common.list includes Docker, Compose and Tomo's dependencies" {
    local list="${REPO_ROOT}/config/packages-common.list"
    for pkg in docker-ce docker-ce-cli containerd.io docker-compose-plugin \
               nodejs git openssl; do
        grep -qx "${pkg}" "${list}"
    done
}

@test "target package lists do not duplicate the Docker packages" {
    run grep -qx "docker-ce" "${REPO_ROOT}/config/packages-rpi5.list"
    [ "$status" -ne 0 ]
    run grep -qx "docker-ce" "${REPO_ROOT}/config/packages-x86_64.list"
    [ "$status" -ne 0 ]
}

@test "build.sh adds the Docker repo for every target" {
    # shellcheck disable=SC2016  # literal match on script source
    grep -q 'install_docker_repo "${ROOTFS}"' "${REPO_ROOT}/build.sh"
    run grep -q 'install_docker_repo' "${REPO_ROOT}/scripts/rpi5/configure-repos.sh"
    [ "$status" -ne 0 ]
}

@test "common customize-rootfs.sh enables Docker for every target" {
    # shellcheck disable=SC2016  # literal match on script source
    grep -q 'enable_docker_units "${ROOTFS}"' \
        "${REPO_ROOT}/scripts/common/customize-rootfs.sh"
}
