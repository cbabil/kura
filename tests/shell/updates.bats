#!/usr/bin/env bats
# tests/shell/updates.bats — what the login screen and the message after
# login say about updates (scripts/common/updates.sh, ADR-025): a newer Kura
# version in the repository, which the owner installs when they choose.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/updates.sh"
}

policy() { apt-cache() { printf '%s\n' "kura:" "  Installed: $INSTALLED" "  Candidate: $CANDIDATE" "  Version table:"; }; }

@test "newer_version: the repository's version when it is newer than the one installed" {
    INSTALLED=0.6.0 CANDIDATE=0.6.1; policy
    [ "$(newer_version kura)" = "0.6.1" ]
}

@test "newer_version: nothing when up to date, not installed, or apt cannot say" {
    INSTALLED=0.6.1 CANDIDATE=0.6.1; policy
    [ -z "$(newer_version kura)" ]
    INSTALLED="(none)" CANDIDATE="(none)"; policy
    [ -z "$(newer_version kura)" ]
    apt-cache() { return 100; }
    run newer_version kura
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the login screen and the message after login both get updates.sh" {
    file_has "${REPO_ROOT}/scripts/common/install-firstboot.sh" "updates.sh"
    file_has "${REPO_ROOT}/scripts/common/kura-issue" "updates.sh"
    file_has "${REPO_ROOT}/scripts/common/kura-issue" "LOGIN_UPGRADE="
    file_has "${REPO_ROOT}/scripts/common/kura-issue" "LOGIN_RESTART="
}
