#!/usr/bin/env bats
# basic/15-temps-alias.sh — the 'b-temp' alias lands in aliases.local only.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    fake_cmd temps 'exit 0'
    mkdir -p "$HOME/.bash"
    : > "$HOME/.bash/bash-alias"
    OLD="$HOME/.bash/bash-alias.local"
    printf '# aliases.local\n' > "$BLE_ALIASES_LOCAL"
}

@test "15-temps: the alias goes to aliases.local only, once" {
    bash "$REPO/basic/15-temps-alias.sh" </dev/null
    bash "$REPO/basic/15-temps-alias.sh" </dev/null
    [ "$(grep -c '^alias b-temp="temps"$' "$BLE_ALIASES_LOCAL")" -eq 1 ]
    [ ! -e "$OLD" ]
}

@test "15-temps: a b-temp an older run put in bash-alias.local moves to aliases.local" {
    printf "alias ll='ls -l'\n\n%s\n%s\n%s\n" \
        '# CPU/GPU temperature logger (temperature-logger). Added by' \
        '# best-linux-environment because this machine has temps installed.' \
        'alias b-temp="temps"' > "$OLD"
    bash "$REPO/basic/15-temps-alias.sh" </dev/null
    [ "$(cat "$OLD")" = "alias ll='ls -l'" ]
    grep -qx 'alias b-temp="temps"' "$BLE_ALIASES_LOCAL"
}

@test "15-temps: a temps alias of yours is left alone" {
    echo "alias t='temps --watch'" > "$BLE_ALIASES_LOCAL"
    bash "$REPO/basic/15-temps-alias.sh" </dev/null
    [ "$(cat "$BLE_ALIASES_LOCAL")" = "alias t='temps --watch'" ]
}
