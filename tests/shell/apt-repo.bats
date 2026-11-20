#!/usr/bin/env bats
# tests/shell/apt-repo.bats — Kura's own apt repository (ADR-025): release
# assets laid out as a flat repository, signed with the Kura Archive key,
# and the source every image has for it.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
FPR="BEDAAE58BB6B8D7A6221435194D0EA5CB90A6B6E"

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/kura-repo.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}"
}

@test "the archive key in the repo is the pinned one, and only it" {
    [ "${KURA_GPG_FINGERPRINT}" = "${FPR}" ]
    run gpg --show-keys --with-colons "${KURA_KEY_FILE}"
    [ "$(grep -c '^pub' <<< "$output")" -eq 1 ]
    output_has "${FPR}"
}

@test "install_kura_repo: the pinned key and a source for the latest release's assets" {
    run install_kura_repo "${ROOTFS}" kura cbabil/kura
    [ "$status" -eq 0 ]
    grep -q "BEGIN PGP PUBLIC KEY BLOCK" "${ROOTFS}/usr/share/keyrings/kura-archive.asc"
    local src="${ROOTFS}/etc/apt/sources.list.d/kura.sources"
    file_has "${src}" "Types: deb"
    file_has "${src}" "URIs: https://github.com/cbabil/kura/releases/latest/download/"
    file_has "${src}" "Suites: ./"
    file_has "${src}" "Signed-By: /usr/share/keyrings/kura-archive.asc"
}

@test "install_kura_repo: the repository may only supply the kura package, nothing of Debian's" {
    install_kura_repo "${ROOTFS}" kura cbabil/kura
    local pref="${ROOTFS}/etc/apt/preferences.d/kura-archive"
    [ "$(grep -v '^#' "${pref}")" = "Package: *
Pin: release o=Kura
Pin-Priority: -1

Package: kura
Pin: release o=Kura
Pin-Priority: 500" ]
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    run kura_owned "${ROOTFS}" kura
    output_has "etc/apt/preferences.d/kura-archive"
}

@test "install_kura_repo: a key file without the pinned key is refused" {
    KURA_GPG_FINGERPRINT="0000000000000000000000000000000000000000"
    run install_kura_repo "${ROOTFS}" kura cbabil/kura
    [ "$status" -ne 0 ]
    [ ! -e "${ROOTFS}/etc/apt/sources.list.d/kura.sources" ]
}

@test "Kura versions are not installed by the automatic updates (the owner asks for them)" {
    run grep -rn "origin=Kura" "${REPO_ROOT}/scripts"
    [ "$status" -ne 0 ]
}

@test "the key and the source belong to the package, so a later version can change them" {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/packaging/kura-package.sh"
    install_kura_repo "${ROOTFS}" kura cbabil/kura
    run kura_owned "${ROOTFS}" kura
    output_has "usr/share/keyrings/kura-archive.asc"
    output_has "etc/apt/sources.list.d/kura.sources"
    file_has "${REPO_ROOT}/scripts/common/customize-rootfs.sh" "install_kura_repo"
}

# ---- make-apt-repo.sh: the release's repository files ----

stub_debs() {  # two packages, with dpkg-scanpackages standing in for the real one
    DIST="${BATS_TEST_TMPDIR}/dist"
    mkdir -p "${DIST}" "${BATS_TEST_TMPDIR}/bin"
    echo amd64 > "${DIST}/kura_0.6.0_amd64.deb"
    echo arm64 > "${DIST}/kura_0.6.0_arm64.deb"
    cat > "${BATS_TEST_TMPDIR}/bin/dpkg-scanpackages" <<'STUB'
#!/bin/sh
for f in ./*.deb; do printf 'Package: kura\nFilename: %s\n\n' "$f"; done
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-scanpackages"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "make-apt-repo: Packages for every .deb, and a Release that names Kura and hashes Packages" {
    stub_debs
    run "${REPO_ROOT}/scripts/release/make-apt-repo.sh" "${DIST}"
    [ "$status" -eq 0 ]
    file_has "${DIST}/Packages" "Filename: ./kura_0.6.0_amd64.deb"
    file_has "${DIST}/Packages" "Filename: ./kura_0.6.0_arm64.deb"
    local rel="${DIST}/Release" sum size
    file_has "${rel}" "Origin: Kura"
    file_has "${rel}" "Label: Kura"
    file_has "${rel}" "Architectures: amd64 arm64"
    grep -q "^Date: " "${rel}"
    sum=$(shasum -a 256 "${DIST}/Packages" | cut -d' ' -f1)
    size=$(wc -c < "${DIST}/Packages" | tr -d ' ')
    file_has "${rel}" " ${sum} ${size} Packages"
}

@test "make-apt-repo: with a signing key, InRelease is the signed Release and checks against the key" {
    stub_debs
    local home="${BATS_TEST_TMPDIR}/g"   # a throwaway key: the real one is only in CI
    mkdir -m 700 "${home}"
    GNUPGHOME="${home}" gpg --batch --quiet --pinentry-mode loopback --passphrase '' --allow-freeform-uid \
        --quick-generate-key "Test Archive" ed25519 sign 1d 2>/dev/null || skip "no gpg agent here"
    local fpr
    fpr=$(GNUPGHOME="${home}" gpg --batch --list-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
    GNUPGHOME="${home}" run "${REPO_ROOT}/scripts/release/make-apt-repo.sh" "${DIST}" "${fpr}"
    [ "$status" -eq 0 ]
    grep -q "BEGIN PGP SIGNED MESSAGE" "${DIST}/InRelease"
    GNUPGHOME="${home}" gpg --batch --verify "${DIST}/InRelease" 2>/dev/null
}

@test "the release publishes the repository files and the packages, signed" {
    local wf="${REPO_ROOT}/.github/workflows/release.yml"
    file_has "${wf}" "make-apt-repo.sh"
    file_has "${wf}" "KURA_APT_KEY"
    file_has "${wf}" "InRelease"
    # the images workflow hands the packages over with the images
    file_has "${REPO_ROOT}/.github/workflows/images.yml" "-name '*.deb'"
}
