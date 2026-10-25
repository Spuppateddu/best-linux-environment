#!/usr/bin/env bats
# basic/16-fastnote-alias.sh — the secondary 'fn' alias: install, --check, --uninstall.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    fake_cmd vim 'exit 0'
    mkdir -p "$HOME/.bash"
    : > "$HOME/.bash/bash-alias"
    OLD="$HOME/.bash/bash-alias.local"
    printf '# aliases.local\n' > "$BLE_ALIASES_LOCAL"
}

@test "16-fastnote: --check is no until the alias is added, then yes" {
    run bash "$REPO/basic/16-fastnote-alias.sh" --check
    [ "$status" -eq 1 ]
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    grep -q "^alias fn=" "$BLE_ALIASES_LOCAL"
    run bash "$REPO/basic/16-fastnote-alias.sh" --check
    [ "$status" -eq 0 ]
}

@test "16-fastnote: the alias goes to aliases.local only, never to <shell>-alias.local" {
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    grep -q "^alias fn=" "$BLE_ALIASES_LOCAL"
    [ ! -e "$OLD" ]
}

@test "16-fastnote: a second run adds nothing" {
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    [ "$(grep -c '^alias fn=' "$BLE_ALIASES_LOCAL")" -eq 1 ]
}

@test "16-fastnote: an fn an older run put in bash-alias.local moves to aliases.local" {
    printf "alias ll='ls -l'\n\n%s\n%s\n%s\n" \
        '# Quick scratch note: create/open ~/fastnote.txt in vim. Added by' \
        '# best-linux-environment.' \
        "alias fn='touch ~/fastnote.txt && vim ~/fastnote.txt'" > "$OLD"
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    [ "$(cat "$OLD")" = "alias ll='ls -l'" ]
    grep -q "^alias fn=" "$BLE_ALIASES_LOCAL"
}

@test "16-fastnote: --uninstall removes our lines and keeps yours" {
    printf 'alias ll=%s\n' "'ls -l'" > "$BLE_ALIASES_LOCAL"
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    run bash "$REPO/basic/16-fastnote-alias.sh" --uninstall
    [ "$status" -eq 0 ]
    [ "$(cat "$BLE_ALIASES_LOCAL")" = "alias ll='ls -l'" ]
    run bash "$REPO/basic/16-fastnote-alias.sh" --check
    [ "$status" -eq 1 ]
}

@test "16-fastnote: --uninstall leaves an fn alias you wrote yourself" {
    echo "alias fn='vim ~/notes/fastnote.txt'" > "$BLE_ALIASES_LOCAL"
    run bash "$REPO/basic/16-fastnote-alias.sh" --uninstall
    [ "$status" -eq 0 ]
    grep -qx "alias fn='vim ~/notes/fastnote.txt'" "$BLE_ALIASES_LOCAL"
}

@test "modules.conf: fastnote is a secondary app, so it can be unticked" {
    grep -q '^secondary|fastnote|all|script|' "$REPO/modules.conf"
}
