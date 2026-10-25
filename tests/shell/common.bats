#!/usr/bin/env bats
# tests/shell/common.bats — tests for lib/common.sh validation functions

setup() {
    load test_helper
    load_security_lib "common"
}

# ---- validate_name ----

@test "validate_name: accepts simple alphanumeric" {
    run validate_name "myprofile"
    [ "$status" -eq 0 ]
}

@test "validate_name: accepts name with dots" {
    run validate_name "my.profile"
    [ "$status" -eq 0 ]
}

@test "validate_name: accepts name with underscores" {
    run validate_name "my_profile"
    [ "$status" -eq 0 ]
}

@test "validate_name: accepts name with hyphens" {
    run validate_name "my-profile"
    [ "$status" -eq 0 ]
}

@test "validate_name: accepts name starting with digit" {
    run validate_name "1profile"
    [ "$status" -eq 0 ]
}

@test "validate_name: accepts mixed alphanumeric with all allowed chars" {
    run validate_name "App.armor_profile-v2"
    [ "$status" -eq 0 ]
}

@test "validate_name: rejects empty string" {
    run validate_name ""
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name starting with dot" {
    run validate_name ".hidden"
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name starting with hyphen" {
    run validate_name "-bad"
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name with slash (path traversal)" {
    run validate_name "../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name with space" {
    run validate_name "my profile"
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name with shell metacharacter" {
    run validate_name 'test;rm -rf /'
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name with backtick" {
    run validate_name 'test`id`'
    [ "$status" -eq 1 ]
}

# ---- write_file ----

@test "write_file: creates file with default 0644 permissions" {
    local dest="${BATS_TEST_TMPDIR}/testfile"
    echo "hello" | write_file "${dest}"
    [ -f "${dest}" ]
    [ "$(cat "${dest}")" = "hello" ]
}

# ---- log functions ----

@test "log_info: outputs to stdout" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [ "$output" = "INFO:  test message" ]
}

@test "log_warning: outputs to stderr" {
    run log_warning "warn message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: warn message"* ]]
}

@test "log_error: outputs to stderr" {
    run log_error "error message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: error message"* ]]
}
