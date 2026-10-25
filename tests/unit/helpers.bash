# Shared by every .bats file. Each test gets its own HOME and a fake bin/ first on
# PATH, so dpkg, apt and sudo are stand-ins: nothing real is installed or removed.

REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export BLE_STATE_DIR="$HOME/.cache/best-linux-environment"
    export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    # What the fake package manager knows: one `PACKAGE STATUS` per line.
    export FAKE_DPKG="$BATS_TEST_TMPDIR/dpkg-status"
    # Every fake apt-get / sudo call lands here, one per line, for assertions.
    export FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
    # Modules append aliases here: never the repo's own aliases.local.
    export BLE_ALIASES_LOCAL="$BATS_TEST_TMPDIR/aliases.local"
    mkdir -p "$HOME" "$FAKE_BIN"
    : > "$FAKE_DPKG"; : > "$FAKE_LOG"
    export PATH="$FAKE_BIN:$PATH"
    unset BLE_PROFILE BLE_ANSWERS BLE_SHELL DRY_RUN

    # `dpkg-query -W -f='${db:Status-Status}' PKG`: the status, or exit 1 if unknown.
    fake_cmd dpkg-query 'pkg="${!#}"; st="$(awk -v p="$pkg" '\''$1==p {print $2}'\'' "$FAKE_DPKG")"
        [[ -n "$st" ]] || exit 1; printf "%s" "$st"'
    # dpkg -s says yes to anything it knows, "rc" included — the real behaviour.
    fake_cmd dpkg '[[ "$1" == -s ]] && grep -q "^$2 " "$FAKE_DPKG"'
    fake_cmd apt-get 'echo "apt-get $*" >> "$FAKE_LOG"'
    fake_cmd apt-cache 'echo "  Candidate: 1.0"'
    fake_cmd sudo '[[ "$1" == -n ]] && shift; echo "sudo $*" >> "$FAKE_LOG"; "$@"'
}

# fake_cmd NAME BODY  — put a bash script called NAME first on PATH.
fake_cmd() {
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE_BIN/$1"
    chmod +x "$FAKE_BIN/$1"
}

# pkg_status PACKAGE STATUS  — tell the fake dpkg about one package.
pkg_status() { echo "$1 $2" >> "$FAKE_DPKG"; }

# ble CODE  — run CODE in a fresh bash with the repo's libs sourced, so their
# `set -euo pipefail` never leaks into bats itself.
ble() {
    run bash -c "source '$REPO/lib/common.sh'; source '$REPO/lib/ui.sh'; source '$REPO/lib/registry.sh'; $1"
}
