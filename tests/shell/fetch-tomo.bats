#!/usr/bin/env bats
# tests/shell/fetch-tomo.bats — tests for scripts/common/fetch-tomo.sh
# (download + verify the pinned Tomo release .deb installed into the image)

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    unset OS_TOMO_VERSION OS_TOMO_SHA256_ARM64 OS_TOMO_SHA256_AMD64 OS_TOMO_DEB
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/fetch-tomo.sh"
    CACHE="${BATS_TEST_TMPDIR}/cache"
    FAKE_DEB="${BATS_TEST_TMPDIR}/fake.deb"
    printf 'not really a deb\n' > "${FAKE_DEB}"
    FAKE_SHA=$(file_sha256 "${FAKE_DEB}")
    # Signature checks are covered by sigstore.bats and the bundle tests below
    sigstore_verify() { :; }
}

# ---- tomo_deb_url ----

@test "tomo_deb_url: GitHub release asset URL" {
    run tomo_deb_url 0.0.76 arm64
    [ "$output" = "https://github.com/cbabil/tomo/releases/download/v0.0.76/tomo_0.0.76_arm64.deb" ]
}

# ---- tomo_version / tomo_expected_sha ----

@test "tomo_version: defaults to the pinned release" {
    run tomo_version
    [ "$output" = "${TOMO_DEFAULT_VERSION}" ]
}

@test "tomo_version: rejects a non-semver override" {
    OS_TOMO_VERSION="latest"
    run tomo_version
    [ "$status" -eq 1 ]
    output_has "invalid OS_TOMO_VERSION"
}

@test "tomo_expected_sha: pinned default per arch" {
    run tomo_expected_sha arm64
    [ "$output" = "${TOMO_DEFAULT_SHA256_ARM64}" ]
    run tomo_expected_sha amd64
    [ "$output" = "${TOMO_DEFAULT_SHA256_AMD64}" ]
}

@test "tomo_expected_sha: override must be 64 hex chars" {
    OS_TOMO_SHA256_ARM64="abc123"
    run tomo_expected_sha arm64
    [ "$status" -eq 1 ]
    output_has "invalid OS_TOMO_SHA256_ARM64"
}

@test "tomo_expected_sha: changing the version requires a new checksum" {
    OS_TOMO_VERSION="0.0.99"
    run tomo_expected_sha arm64
    [ "$status" -eq 1 ]
    output_has "OS_TOMO_SHA256_ARM64"
}

# ---- fetch_tomo_deb ----

@test "fetch_tomo_deb: downloads the pinned URL and verifies it" {
    stub_curl_copy "${FAKE_DEB}"
    CURL_BUNDLE_SRC="${BATS_TEST_TMPDIR}/bundle.json"; echo '{}' > "${CURL_BUNDLE_SRC}"
    OS_TOMO_VERSION="0.0.99"
    OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${CACHE}/tomo_0.0.99_arm64.deb" ]
    [ "$(head -1 "${BATS_TEST_TMPDIR}/curl-url")" = \
      "https://github.com/cbabil/tomo/releases/download/v0.0.99/tomo_0.0.99_arm64.deb" ]
}

@test "fetch_tomo_deb: rejects a download with the wrong checksum" {
    stub_curl_copy "${FAKE_DEB}"
    OS_TOMO_VERSION="0.0.99"
    OS_TOMO_SHA256_ARM64="$(printf '0%.0s' {1..64})"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 1 ]
    output_has "checksum mismatch"
    [ ! -e "${CACHE}/tomo_0.0.99_arm64.deb" ]
}

@test "fetch_tomo_deb: reuses a cached file with the right checksum" {
    # shellcheck disable=SC2329  # would be called if the cache were ignored
    curl() { echo "curl must not run" >&2; return 1; }
    OS_TOMO_VERSION="0.0.99"
    OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    mkdir -p "${CACHE}"
    cp "${FAKE_DEB}" "${CACHE}/tomo_0.0.99_arm64.deb"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${CACHE}/tomo_0.0.99_arm64.deb" ]
}

@test "fetch_tomo_deb: fails when the download fails" {
    # shellcheck disable=SC2329  # invoked by fetch_tomo_deb
    curl() { return 22; }
    OS_TOMO_VERSION="0.0.99"
    OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 1 ]
    output_has "failed to download"
}

@test "fetch_tomo_deb: OS_TOMO_DEB uses a local build without downloading" {
    # shellcheck disable=SC2329  # would be called if the override were ignored
    curl() { echo "curl must not run" >&2; return 1; }
    OS_TOMO_DEB="${FAKE_DEB}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${FAKE_DEB}" ]
    output_has "local Tomo package"
}

@test "fetch_tomo_deb: OS_TOMO_DEB must exist" {
    OS_TOMO_DEB="${BATS_TEST_TMPDIR}/missing.deb"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 1 ]
    output_has "not found"
}

# ---- Sigstore bundle (signed Tomo releases) ----

@test "fetch_tomo_deb: verifies the release's Sigstore bundle when it exists" {
    stub_curl_copy "${FAKE_DEB}"
    CURL_BUNDLE_SRC="${BATS_TEST_TMPDIR}/bundle.json"; echo '{}' > "${CURL_BUNDLE_SRC}"
    sigstore_verify() { echo "verify $*" >> "${BATS_TEST_TMPDIR}/verify-calls"; }
    OS_TOMO_VERSION="0.0.99"; OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 0 ]
    matches "$(cat "${BATS_TEST_TMPDIR}/verify-calls")" \
        "verify ${CACHE}/tomo_0.0.99_arm64.deb.partial ${CACHE}/tomo_0.0.99_arm64.deb.partial.sigstore.json cbabil/tomo release.yml v0.0.99"
    file_has "${BATS_TEST_TMPDIR}/curl-url" \
        "https://github.com/cbabil/tomo/releases/download/v0.0.99/tomo_0.0.99_arm64.deb.sigstore.json"
    output_has "signature verified"
    # build.sh captures stdout as the .deb path: the last line must be exactly that
    [ "${lines[${#lines[@]}-1]}" = "${CACHE}/tomo_0.0.99_arm64.deb" ]
    # the bundle was only needed for the check
    [ ! -e "${CACHE}/tomo_0.0.99_arm64.deb.partial.sigstore.json" ]
}

@test "fetch_tomo_deb: a bundle download error other than 404 is fatal, not 'unsigned'" {
    stub_curl_copy "${FAKE_DEB}"
    CURL_BUNDLE_CODE=503
    OS_TOMO_VERSION="0.0.99"; OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -ne 0 ]
    output_has "could not download"
    [ ! -e "${CACHE}/tomo_0.0.99_arm64.deb" ]
}

@test "fetch_tomo_deb: a missing bundle is fatal for any version but the unsigned pinned default" {
    stub_curl_copy "${FAKE_DEB}"
    OS_TOMO_VERSION="0.0.99"; OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -ne 0 ]
    output_has "must be signed"
    [ ! -e "${CACHE}/tomo_0.0.99_arm64.deb" ]
}

@test "fetch_tomo_deb: refuses a release whose bundle does not verify" {
    stub_curl_copy "${FAKE_DEB}"
    CURL_BUNDLE_SRC="${BATS_TEST_TMPDIR}/bundle.json"; echo '{}' > "${CURL_BUNDLE_SRC}"
    # shellcheck disable=SC2329  # invoked by fetch_tomo_deb
    sigstore_verify() { return 1; }
    OS_TOMO_VERSION="0.0.99"; OS_TOMO_SHA256_ARM64="${FAKE_SHA}"
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -ne 0 ]
    [ ! -e "${CACHE}/tomo_0.0.99_arm64.deb" ]
    [ ! -e "${CACHE}/tomo_0.0.99_arm64.deb.partial" ]
}

@test "fetch_tomo_deb: the pinned default predates signing: warns and relies on the sha256 pin" {
    stub_curl_copy "${FAKE_DEB}"
    # shellcheck disable=SC2329  # must not be called
    sigstore_verify() { echo "must not verify" >&2; return 1; }
    OS_TOMO_SHA256_ARM64="${FAKE_SHA}"   # the pinned version, our fake bytes
    run fetch_tomo_deb arm64 "${CACHE}"
    [ "$status" -eq 0 ]
    output_has "not signed"
    [ -f "${CACHE}/tomo_${TOMO_DEFAULT_VERSION}_arm64.deb" ]
}
