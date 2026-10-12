#!/usr/bin/env bash
# Every test, in Docker, so this machine is never touched. `./tests/run.sh` runs
# lint + unit (seconds); `e2e` runs the real ./setup.sh in a fresh Ubuntu (minutes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/tests"

usage() {
    cat <<'EOF'
Usage: ./tests/run.sh [lint|unit|e2e|all]...
  (none)  lint + unit — run after every change
  lint    shellcheck on every shell script in the repo
  unit    the bats tests in tests/unit/ (apt and sudo are faked)
  e2e     ./setup.sh for real in a fresh Ubuntu container: install, uninstall, re-run
  all     lint + unit + e2e — before you push a change to setup.sh or a module
EOF
}

command -v docker >/dev/null || { echo "✗ Docker is needed: ./setup.sh only docker" >&2; exit 1; }

# Built once, then Docker's cache makes this a no-op.
image() {
    docker build -q --target "$1" -t "ble-test-$1" "$TESTS" >/dev/null
}

# The repo's shell scripts: tracked or new, not gitignored, with a sh/bash shebang.
shell_files() {
    git -C "$ROOT" ls-files -co --exclude-standard | while read -r f; do
        [[ -f "$ROOT/$f" ]] && head -n1 "$ROOT/$f" | grep -q '^#!.*\(bash\|sh\)$' && printf '%s\n' "$f"
    done
}

lint() {
    echo "══ lint: shellcheck ══"
    image tools
    local files; mapfile -t files < <(shell_files)
    docker run --rm -v "$ROOT:/repo:ro" -w /repo ble-test-tools \
        shellcheck -x -S warning "${files[@]}"
    echo "✓ ${#files[@]} scripts clean"
}

unit() {
    echo "══ unit: bats ══"
    image tools
    docker run --rm -v "$ROOT:/repo:ro" -w /repo ble-test-tools bats tests/unit
}

e2e() {
    echo "══ e2e: ./setup.sh in a fresh Ubuntu ══"
    image fresh
    bash "$TESTS/e2e/run-e2e.sh"
}

[[ $# -eq 0 ]] && set -- lint unit
for what in "$@"; do
    case "$what" in
        lint|unit|e2e) "$what" ;;
        all) lint; unit; e2e ;;
        -h|--help|help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
echo "✓ all passed"
