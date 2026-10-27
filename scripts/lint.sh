#!/usr/bin/env bash
# scripts/lint.sh - static checks for the project.
#   1. required files exist
#   2. every Bash script passes "bash -n" (syntax check)
#   3. ShellCheck, if it is installed (warnings and errors fail the lint)
#
# Usage: ./scripts/lint.sh
# Exits 0 if everything is clean, 1 if any check fails.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

FAILED=0

ok()  { echo "OK:   $1"; }
bad() { echo "FAIL: $1"; FAILED=1; }

# ---------- 1. required files ----------
echo "== Required files =="
required_files=(
    README.md
    app/app.sh
    scripts/lint.sh
    scripts/build.sh
    tests/test.sh
    Dockerfile
    compose.yaml
    .dockerignore
    .github/workflows/ci.yml
)
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        ok "$file exists"
    else
        bad "$file is missing"
    fi
done
echo

# all the bash scripts in the project
scripts=(app/*.sh scripts/*.sh tests/*.sh)

# ---------- 2. bash syntax ----------
echo "== Bash syntax (bash -n) =="
for script in "${scripts[@]}"; do
    [[ -f "$script" ]] || continue
    if bash -n "$script" 2>/tmp/lint-syntax.err; then
        ok "$script"
    else
        bad "$script has a syntax error:"
        sed 's/^/      /' /tmp/lint-syntax.err
    fi
done
rm -f /tmp/lint-syntax.err
echo

# ---------- 3. shellcheck (optional) ----------
echo "== ShellCheck =="
if command -v shellcheck >/dev/null 2>&1; then
    # -S warning: report warnings and errors, ignore style/info hints
    if shellcheck -S warning "${scripts[@]}"; then
        ok "shellcheck found no problems"
    else
        bad "shellcheck reported problems (see above)"
    fi
else
    echo "SKIP: shellcheck is not installed"
fi
echo

if (( FAILED )); then
    echo "Lint FAILED"
    exit 1
fi
echo "Lint passed"
exit 0
