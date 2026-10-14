#!/usr/bin/env bats
# blank-screen/b-blank (turn a workspace off and on) and basic/63-blank-screen.sh.

load helpers

eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    # The fake i3 knows the workspaces in $FAKE_WS; every command goes to the log.
    export FAKE_WS="$BATS_TEST_TMPDIR/workspaces.json"
    fake_cmd i3-msg '[[ "$1" == -t ]] && { cat "$FAKE_WS"; exit; }; echo "i3-msg $*" >> "$FAKE_LOG"'
}

# workspaces FOCUSED [OTHER...]  — the workspaces i3 reports, the first one focused.
workspaces() {
    jq -n '$ARGS.positional | to_entries | map({name: .value, focused: (.key == 0)})' \
        --args "$@" > "$FAKE_WS"
}

@test "blank: off keeps the windows in off-N and shows an empty N" {
    workspaces "3" "1"
    run "$REPO/blank-screen/b-blank"
    [ "$status" -eq 0 ]
    diff <(cat "$FAKE_LOG") - <<'LOG'
i3-msg rename workspace "3" to "off-3"
i3-msg workspace --no-auto-back-and-forth "3"
LOG
}

@test "blank: on, from the empty N, gives the windows their name back" {
    workspaces "3" "off-3"
    run "$REPO/blank-screen/b-blank"
    [ "$status" -eq 0 ]
    grep -q 'i3-msg rename workspace "3" to "off-3-' "$FAKE_LOG"
    grep -qx 'i3-msg rename workspace "off-3" to "3"' "$FAKE_LOG"
    [ "$(tail -n1 "$FAKE_LOG")" = 'i3-msg workspace --no-auto-back-and-forth "3"' ]
}

@test "blank: on, from off-N itself, turns N back on" {
    workspaces "off-3" "1"
    run "$REPO/blank-screen/b-blank"
    [ "$status" -eq 0 ]
    grep -qx 'i3-msg rename workspace "off-3" to "3"' "$FAKE_LOG"
}

@test "blank: a name with quotes is escaped for i3" {
    workspaces 'say "hi"'
    "$REPO/blank-screen/b-blank"
    grep -qxF 'i3-msg rename workspace "say \"hi\"" to "off-say \"hi\""' "$FAKE_LOG"
}

@test "blank: the label is the PC's name, 8 bits per letter" {
    fake_cmd hostname 'echo ab'
    run "$REPO/blank-screen/b-blank" label-text
    [ "$output" = "01100001 01100010" ]
}

@test "blank: no i3 answer stops with an error" {
    echo '[]' > "$FAKE_WS"
    run "$REPO/blank-screen/b-blank"
    [ "$status" -eq 1 ]
}

@test "blank: the module binds \$mod+x in i3's config" {
    mkdir -p "$HOME/.i3rc"
    # The repo is mounted read-only and the module chmods the script: run a copy.
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/blank-screen"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/63-blank-screen.sh" "$copy/basic/"
    cp "$REPO/blank-screen/b-blank" "$copy/blank-screen/"
    run bash "$copy/basic/63-blank-screen.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'bindsym $mod+x exec --no-startup-id ~/.local/bin/b-blank' \
        "$HOME/.i3rc/10-blank-screen.local"
    grep -qx 'no_focus \[class="^b-blank-label\$"\]' "$HOME/.i3rc/10-blank-screen.local"
    [ -L "$HOME/.local/bin/b-blank" ]
}

@test "blank: N turned off while empty has no off-N; on just drops its label" {
    workspaces "3"
    # The tree: workspace 3 holds only the label window.
    fake_cmd i3-msg '[[ "$1" == -t && "$2" == get_tree ]] && { echo "{\"type\":\"workspace\",\"name\":\"3\",\"nodes\":[{\"id\":42,\"window_properties\":{\"class\":\"b-blank-label\"}}]}"; exit; }
        [[ "$1" == -t ]] && { cat "$FAKE_WS"; exit; }; echo "i3-msg $*" >> "$FAKE_LOG"'
    run "$REPO/blank-screen/b-blank"
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_LOG")" = 'i3-msg [con_id=42] kill' ]
}
