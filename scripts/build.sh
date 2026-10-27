#!/usr/bin/env bash
# scripts/build.sh - builds the Docker image and smoke-tests it.
#
# Usage: ./scripts/build.sh
#        IMAGE=my-tag ./scripts/build.sh   (use a different image name)
#
# Exits 0 if the build and all smoke tests pass, 1 otherwise.

set -u

IMAGE="${IMAGE:-devops-tool}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed"
    exit 1
fi

# ---------- build ----------
echo "== Building image: $IMAGE =="
if ! docker build -t "$IMAGE" .; then
    echo "FAIL: docker build failed"
    exit 1
fi
echo

# ---------- smoke tests ----------
echo "== Smoke tests =="
FAILED=0

# smoke <name> <expected exit code> <arguments for the container...>
smoke() {
    local name="$1"
    local expected_rc="$2"
    shift 2

    docker run --rm "$IMAGE" "$@" >/tmp/smoke.log 2>&1
    local rc=$?

    if [[ $rc -eq $expected_rc ]]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (exit code $rc, expected $expected_rc)"
        sed 's/^/      /' /tmp/smoke.log
        FAILED=1
    fi
}

smoke "help works"                       0 help
smoke "system-info works"                0 system-info
smoke "no command shows help (CMD)"      0
smoke "check-host localhost works"       0 check-host localhost
smoke "invalid command returns 2"        2 invalid-command
smoke "non-numeric port returns 2"       2 check-port localhost abc
smoke "port 0 returns 2"                 2 check-port localhost 0

# the container should run as a normal user, not root
user=$(docker run --rm --entrypoint id "$IMAGE" -u 2>/dev/null)
if [[ -n "$user" && "$user" != "0" ]]; then
    echo "PASS: container runs as non-root user (uid $user)"
else
    echo "FAIL: container runs as root"
    FAILED=1
fi

rm -f /tmp/smoke.log
echo

if (( FAILED )); then
    echo "Build/smoke tests FAILED"
    exit 1
fi
echo "Build and smoke tests passed"
exit 0
