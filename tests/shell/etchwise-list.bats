#!/usr/bin/env bats
# tests/shell/etchwise-list.bats — scripts/release/make-etchwise-list.sh turns
# the release manifest into the OS list Etchwise reads (Raspberry Pi Imager's
# v4 format): one Kura entry for the Pi 5, with first-boot setup ("kura").

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SCRIPT="${REPO_ROOT}/scripts/release/make-etchwise-list.sh"

setup() {
    load test_helper
    MANIFEST="${BATS_TEST_TMPDIR}/manifest.json"
    cat > "${MANIFEST}" <<'JSON'
{"version":"0.1.0","channel":"stable","released":"2026-10-25","bundles":{
 "rpi5-arm64":{"url":"https://github.com/cbabil/kura/releases/download/v0.1.0/kura-0.1.0-rpi5-arm64.img.zst",
   "sha256":"aa","size":400,"extract_sha256":"bb","extract_size":2000},
 "x86_64":{"url":"https://x/kura.iso","sha256":"cc","size":9,"extract_sha256":"cc","extract_size":9}}}
JSON
}

entry() { echo "$output" | jq -r ".os_list[0]$1"; }

@test "make-etchwise-list: one Pi 5 entry with the image's download and unpacked hashes" {
    run "${SCRIPT}" "${MANIFEST}"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq '.os_list | length')" = "1" ]
    [ "$(entry .name)" = "Kura 0.1.0" ]
    [ "$(entry .url)" = "https://github.com/cbabil/kura/releases/download/v0.1.0/kura-0.1.0-rpi5-arm64.img.zst" ]
    [ "$(entry .image_download_size)" = "400" ]
    [ "$(entry .image_download_sha256)" = "aa" ]
    [ "$(entry .extract_size)" = "2000" ]
    [ "$(entry .extract_sha256)" = "bb" ]
    [ "$(entry .release_date)" = "2026-10-25" ]
    [ "$(entry '.devices | join(",")')" = "pi5-64bit" ]
}

@test "make-etchwise-list: asks Etchwise for Kura's first-boot setup" {
    run "${SCRIPT}" "${MANIFEST}"
    [ "$(entry .init_format)" = "kura" ]
    [ "$(entry '.capabilities | length')" = "0" ]
}

@test "make-etchwise-list: the icon is embedded, so the list needs no other download" {
    run "${SCRIPT}" "${MANIFEST}"
    matches "$(entry .icon)" "data:image/svg+xml;base64,*"
    [ -n "$(entry .description)" ]
}

@test "make-etchwise-list: fails without a manifest" {
    run "${SCRIPT}" "${BATS_TEST_TMPDIR}/missing.json"
    [ "$status" -ne 0 ]
}

@test "release.yml publishes etchwise.json with the other signed assets" {
    local wf="${REPO_ROOT}/.github/workflows/release.yml"
    file_has "${wf}" "make-etchwise-list.sh manifest.json > etchwise.json"
    file_has "${wf}" "SHA512SUMS manifest.json etchwise.json > ASSETS"
}
