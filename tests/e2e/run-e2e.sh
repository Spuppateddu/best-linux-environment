#!/usr/bin/env bash
# ./setup.sh for real, three times, in one fresh Ubuntu container (server profile):
# install an app, untick and uninstall it, then a plain re-run must change nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="ble-e2e-$$"
LOGS="${BLE_E2E_LOGS:-$ROOT/tests/e2e/logs}"
mkdir -p "$LOGS"

# BLE_E2E_KEEP=1 leaves the container up to look inside: docker exec -it NAME bash
cleanup() {
    if [[ "${BLE_E2E_KEEP:-}" == 1 ]]; then
        echo "· Kept: docker exec -it $NAME bash   (docker rm -f $NAME when done)"
    else
        docker rm -f "$NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

docker run -d --name "$NAME" ble-test-fresh sleep infinity >/dev/null

# The working tree as it is now — uncommitted changes included, gitignored files
# (your *.local) left out, and no .git, so self_update's pull just warns.
(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 tar -c 2>/dev/null) \
    | docker exec -i "$NAME" bash -c 'mkdir -p ~/best-linux-environment && tar -x -C ~/best-linux-environment'

in_box() { docker exec -i "$NAME" bash -c "$1"; }

# step NAME ANSWER-LINE…  — one ./setup.sh run with these answers; log kept on disk.
step() {
    local name="$1"; shift
    printf '%s\n' "$@" | in_box 'cat > ~/answers'
    echo "▸ $name"
    local rc=0
    in_box 'cd ~/best-linux-environment && BLE_PROFILE=server BLE_ANSWERS=~/answers bash ./setup.sh </dev/null' \
        > "$LOGS/$name.log" 2>&1 || rc=$?
    if (( rc != 0 )); then
        echo "✗ $name: ./setup.sh exited $rc. Last lines of $LOGS/$name.log:"
        grep -E '✗|!' "$LOGS/$name.log" | tail -20
        exit 1
    fi
}

check() {
    local what="$1" code="$2"
    if in_box "$code" >/dev/null 2>&1; then echo "  ✓ $what"; else echo "  ✗ $what"; exit 1; fi
}

installed() { printf '[[ "$(dpkg-query -W -f="\\${db:Status-Status}" %s 2>/dev/null)" == installed ]]' "$1"; }

# The answers every run shares: bash login shell, no vim languages, no boot cron.
COMMON=('Which shell* | bash*' 'Vim* | -' 'Automation | -' 'Colours | Keep*')

step 1-install "${COMMON[@]}" 'Secondary* | OpenSSH server*'
check "the necessary tier is in (git, curl, zsh)" 'command -v git && command -v curl && command -v zsh'
check "the bash config repo is linked" 'test -L ~/.bash'
check "the ticked app is installed" "$(installed openssh-server)"
check "it is remembered for next time" 'grep -qx sshd ~/.cache/best-linux-environment/chosen'

step 2-uninstall "${COMMON[@]}" 'Secondary* | -' 'Uninstall* | OpenSSH server*'
check "the unticked app is removed" "! $(installed openssh-server)"
check "it is forgotten" '! grep -qx sshd ~/.cache/best-linux-environment/chosen'

step 3-rerun "${COMMON[@]}" 'Secondary* | -'
if grep -q '══ Uninstall' "$LOGS/3-rerun.log"; then echo "  ✗ re-run offered an uninstall"; exit 1; fi
if grep -q 'apt: installing' "$LOGS/3-rerun.log"; then echo "  ✗ re-run installed something again"; exit 1; fi
echo "  ✓ the re-run installed nothing new and offered no uninstall"
echo "✓ e2e passed — logs in ${LOGS/#$HOME/\~}"
