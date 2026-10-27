#!/usr/bin/env bash
# tests/test.sh - tests for app/app.sh
#
# Usage: ./tests/test.sh
# Exits 0 if every test passes, 1 if any test fails.
#
# Tests only use localhost and the reserved ".invalid" domain, so they give
# the same result on any machine, with or without internet.

set -u

# find app.sh relative to this file, so the tests work from any folder
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/app/app.sh"

PASSED=0
FAILED=0

# run_test <name> <expected exit code> <text the output must contain, or ""> <app arguments...>
run_test() {
    local name="$1"
    local expected_rc="$2"
    local expected_text="$3"
    shift 3

    local output rc
    output=$("$APP" "$@" 2>&1)
    rc=$?

    if [[ $rc -ne $expected_rc ]]; then
        echo "FAIL: $name (exit code $rc, expected $expected_rc)"
        echo "$output" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    elif [[ -n "$expected_text" ]] && ! grep -qi -- "$expected_text" <<< "$output"; then
        echo "FAIL: $name (output does not contain '$expected_text')"
        echo "$output" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    else
        echo "PASS: $name"
        PASSED=$((PASSED + 1))
    fi
}

echo "Testing $APP"
echo

# ---------- help ----------
run_test "help shows usage"                      0 "Usage"            help
run_test "--help also shows usage"               0 "Usage"            --help

# ---------- system-info ----------
run_test "system-info succeeds"                  0 "Hostname"         system-info
run_test "system-info shows the kernel"          0 "Kernel"           system-info
run_test "system-info rejects extra arguments"   2 ""                 system-info extra

# ---------- invalid commands ----------
run_test "missing command returns 2"             2 "no command"
run_test "invalid command returns 2"             2 "unknown command"  invalid-command

# ---------- check-host ----------
run_test "check-host without a host returns 2"   2 "needs a host"     check-host
run_test "check-host localhost resolves"         0 "127.0.0.1"        check-host localhost
run_test "check-host accepts an IP address"      0 "127.0.0.1"        check-host 127.0.0.1
run_test "check-host rejects bad characters"     2 "not a valid"      check-host "bad;host"
run_test "check-host unknown host returns 1"     1 "could not resolve" check-host does-not-exist.invalid
run_test "check-host rejects a leading dash"     2 "not a valid"      check-host -badhost

# ---------- check-port: invalid input ----------
run_test "check-port without a port returns 2"   2 "needs a port"     check-port localhost
run_test "check-port non-numeric port returns 2" 2 "1 to 65535"       check-port localhost abc
run_test "check-port port 0 returns 2"           2 "1 to 65535"       check-port localhost 0
run_test "check-port port 65536 returns 2"       2 "1 to 65535"       check-port localhost 65536
run_test "check-port negative port returns 2"    2 "1 to 65535"       check-port localhost -1
run_test "check-port bad host returns 2"         2 "not a valid"      check-port "bad;host" 80

# ---------- check-port: real connections ----------
# port 1 (tcpmux) is practically never open, so this should be "closed"
run_test "check-port closed port returns 1"      1 "closed"           check-port localhost 1

# start a small local server to test an open port (needs python3)
if command -v python3 >/dev/null 2>&1; then
    TEST_PORT=8765
    python3 -m http.server "$TEST_PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
    SERVER_PID=$!
    # stop the server when the script ends, even if it fails
    trap 'kill "$SERVER_PID" 2>/dev/null' EXIT

    # wait up to 5 seconds for the server to start listening
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        "$APP" check-port 127.0.0.1 "$TEST_PORT" >/dev/null 2>&1 && break
        sleep 0.5
    done

    run_test "check-port open port returns 0"    0 "is open"          check-port 127.0.0.1 "$TEST_PORT"
else
    echo "SKIP: check-port open port (python3 not installed)"
fi

# ---------- summary ----------
echo
echo "Passed: $PASSED"
echo "Failed: $FAILED"

[[ $FAILED -eq 0 ]]
