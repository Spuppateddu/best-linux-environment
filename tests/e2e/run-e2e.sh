#!/usr/bin/env bash
# ./setup.sh for real in one fresh Ubuntu container: install an app, untick and
# uninstall it, a re-run must change nothing, then switch to minimal and keep it.
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

# The working tree as it is now: uncommitted changes in (a deleted tracked file skipped),
# gitignored files (your *.local) out, and no .git, so self_update's pull just warns.
(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 tar -c --ignore-failed-read 2>/dev/null) \
    | docker exec -i "$NAME" bash -c 'mkdir -p ~/best-linux-environment && tar -x -C ~/best-linux-environment'

in_box() { docker exec -i "$NAME" bash -c "$1"; }

# step NAME ANSWER-LINE…  — one ./setup.sh run with these answers; log kept on disk.
# PROFILE=… picks BLE_PROFILE (server by default); PROFILE= runs with none at all.
step() {
    local name="$1" profile="${PROFILE-server}"; shift
    printf '%s\n' "$@" | in_box 'cat > ~/answers'
    echo "▸ $name"
    local rc=0
    in_box "cd ~/best-linux-environment && ${profile:+BLE_PROFILE=$profile} BLE_ANSWERS=~/answers bash ./setup.sh </dev/null" \
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

step 1-install "${COMMON[@]}" 'Secondary* | OpenSSH server*' 'Secondary* | fastnote*'
check "the necessary tier is in (git, curl, zsh)" 'command -v git && command -v curl && command -v zsh'
check "the bash config repo is linked" 'test -L ~/.bash'
check "the ticked app is installed" "$(installed openssh-server)"
check "it is remembered for next time" 'grep -qx sshd ~/.cache/best-linux-environment/chosen'
check "the fastnote alias is added" "grep -q '^alias fn=' ~/best-linux-environment/aliases.local"

step 2-uninstall "${COMMON[@]}" 'Secondary* | -' 'Uninstall* | OpenSSH server*' 'Uninstall* | fastnote*'
check "the unticked app is removed" "! $(installed openssh-server)"
check "the fastnote alias is removed" "! grep -q '^alias fn=' ~/best-linux-environment/aliases.local"
check "it is forgotten" '! grep -qx sshd ~/.cache/best-linux-environment/chosen'

step 3-rerun "${COMMON[@]}" 'Secondary* | -'
if grep -q '══ Uninstall' "$LOGS/3-rerun.log"; then echo "  ✗ re-run offered an uninstall"; exit 1; fi
if grep -q 'apt: installing' "$LOGS/3-rerun.log"; then echo "  ✗ re-run installed something again"; exit 1; fi
echo "  ✓ the re-run installed nothing new and offered no uninstall"

PROFILE=minimal step 4-minimal "${COMMON[@]}" 'Secondary* | -'
check "minimal is remembered" 'grep -qx minimal ~/.cache/best-linux-environment/profile'
if grep -q 'Google Chrome' "$LOGS/4-minimal.log"; then echo "  ✗ minimal listed Chrome"; exit 1; fi
echo "  ✓ minimal lists no Chrome"
PROFILE='' step 5-minimal-rerun "${COMMON[@]}" 'Secondary* | -'
if ! grep -q 'minimal profile' "$LOGS/5-minimal-rerun.log"; then echo "  ✗ a plain re-run forgot minimal"; exit 1; fi
echo "  ✓ a plain re-run keeps minimal"
echo "✓ e2e passed — logs in ${LOGS/#$HOME/\~}"
