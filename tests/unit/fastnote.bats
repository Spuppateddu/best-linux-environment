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
    LOCAL="$HOME/.bash/bash-alias.local"
}

@test "16-fastnote: --check is no until the alias is added, then yes" {
    run bash "$REPO/basic/16-fastnote-alias.sh" --check
    [ "$status" -eq 1 ]
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    grep -q "^alias fn=" "$LOCAL"
    run bash "$REPO/basic/16-fastnote-alias.sh" --check
    [ "$status" -eq 0 ]
}

@test "16-fastnote: --uninstall removes our lines and keeps yours" {
    printf 'alias ll=%s\n' "'ls -l'" > "$LOCAL"
    bash "$REPO/basic/16-fastnote-alias.sh" </dev/null
    run bash "$REPO/basic/16-fastnote-alias.sh" --uninstall
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL")" = "alias ll='ls -l'" ]
    run bash "$REPO/basic/16-fastnote-alias.sh" --check
    [ "$status" -eq 1 ]
}

@test "16-fastnote: --uninstall leaves an fn alias you wrote yourself" {
    echo "alias fn='vim ~/notes/fastnote.txt'" > "$LOCAL"
    run bash "$REPO/basic/16-fastnote-alias.sh" --uninstall
    [ "$status" -eq 0 ]
    grep -qx "alias fn='vim ~/notes/fastnote.txt'" "$LOCAL"
}

@test "modules.conf: fastnote is a secondary app, so it can be unticked" {
    grep -q '^secondary|fastnote|all|script|' "$REPO/modules.conf"
}
