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

@test "blank: the label is tiled, so \$mod+hjkl can move focus off a workspace that is off" {
    workspaces "3"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" FAKE_TREE="$BATS_TEST_TMPDIR/tree.json"
    echo '{"type":"workspace","name":"3","nodes":[]}' > "$FAKE_TREE"
    fake_cmd i3-msg '[[ "$1" == -t && "$2" == get_tree ]] && { cat "$FAKE_TREE"; exit; }
        [[ "$1" == -t ]] && { cat "$FAKE_WS"; exit; }; echo "i3-msg $*" >> "$FAKE_LOG"'
    # The fake alacritty maps the label at once, as con 9.
    fake_cmd alacritty '[[ "$1" == msg ]] && exit 1; inst="${2#*,}"
        jq --arg i "$inst" ".nodes += [{id: 9, window_properties: {class: \"b-blank-label\", instance: \$i}}]" "$FAKE_TREE" > "$FAKE_TREE.new" && mv "$FAKE_TREE.new" "$FAKE_TREE"'
    run "$REPO/blank-screen/b-blank"
    [ "$status" -eq 0 ]
    grep -qx 'i3-msg \[con_id=9\] floating disable, border none, move container to workspace "3"' "$FAKE_LOG"
    ! grep -q 'floating enable\|move position' "$FAKE_LOG"
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
    grep -qx 'for_window \[class="^b-blank-label\$"\] floating disable, border none' "$HOME/.i3rc/10-blank-screen.local"
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

# tree FILE: the fake i3 answers get_tree with FILE, get_workspaces with $FAKE_WS.
fake_tree() {
    export FAKE_TREE="$1"
    fake_cmd i3-msg '[[ "$1" == -t && "$2" == get_tree ]] && { cat "$FAKE_TREE"; exit; }
        [[ "$1" == -t ]] && { cat "$FAKE_WS"; exit; }; echo "i3-msg $*" >> "$FAKE_LOG"'
}

# Workspace 3 holds one focused window, con 7 titled vim; the scratchpad is empty.
cover_tree() {
    local tree="$BATS_TEST_TMPDIR/tree.json"
    echo '{"nodes":[{"type":"workspace","name":"3","nodes":[{"id":7,"focused":true,"border":"pixel","current_border_width":4,"name":"vim","window_properties":{"class":"Alacritty","instance":"Alacritty"}}]},
        {"type":"workspace","name":"__i3_scratch","nodes":[]}]}' > "$tree"
    fake_tree "$tree"
}

# The fake alacritty maps at once, as con 9 in the scratchpad, already titled like the window.
# `alacritty msg` fails (no running Alacritty) unless FAKE_MSG_OK is set.
fake_alacritty() {
    fake_cmd alacritty 'echo "alacritty $*" >> "$FAKE_LOG.alacritty"
        if [[ "$1" == msg ]]; then [[ -n "$FAKE_MSG_OK" ]] || exit 1; shift 2; fi
        inst="${2#*,}"; jq --arg i "$inst" ".nodes[1].nodes += [{id: 9, name: \"vim\", border: \"pixel\", current_border_width: 3, window_properties: {class: \"b-blank-cover\", instance: \$i}}]" "$FAKE_TREE" > "$FAKE_TREE.new" && mv "$FAKE_TREE.new" "$FAKE_TREE"'
}

@test "cover: \$mod+z swaps the window with a hidden cover in one redraw" {
    workspaces "3"
    cover_tree
    fake_alacritty
    run "$REPO/blank-screen/b-blank" window
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$FAKE_LOG")" -eq 1 ]
    grep -q -- 'window.title="b-blank-new" .* cover-wait [0-9]* vim$' "$FAKE_LOG.alacritty"
    # --title would lock the title: the cover could never rename itself, and \$mod+z waits 1 s.
    ! grep -q -- '--title' "$FAKE_LOG.alacritty"
    grep -qx 'i3-msg \[con_id=9\] border pixel 4; \[con_id=7\] swap container with con_id 9; \[con_id=7\] mark --add _b-cover-[0-9]*; \[con_id=9\] focus' "$FAKE_LOG"
}

@test "cover: the cover opens in a running Alacritty when one answers, the faster way" {
    workspaces "3"
    cover_tree
    export FAKE_MSG_OK=1
    fake_alacritty
    run "$REPO/blank-screen/b-blank" window
    [ "$status" -eq 0 ]
    grep -q '^alacritty msg create-window --class b-blank-cover,' "$FAKE_LOG.alacritty"
    [ "$(wc -l < "$FAKE_LOG.alacritty")" -eq 1 ]
}

@test "cover: no running Alacritty answers, so a new one starts" {
    workspaces "3"
    cover_tree
    fake_alacritty
    run "$REPO/blank-screen/b-blank" window
    [ "$status" -eq 0 ]
    grep -q '^alacritty msg create-window ' "$FAKE_LOG.alacritty"
    grep -q '^alacritty --class b-blank-cover,' "$FAKE_LOG.alacritty"
}

@test "cover: once hidden, the cover takes the window's title" {
    fake_cmd i3-msg 'echo "i3-msg $*" >> "$FAKE_LOG"'
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
    : > "$BATS_TEST_TMPDIR/b-blank-cover-55.ready"
    run timeout 1 "$REPO/blank-screen/b-blank" cover-wait 55 vim
    [[ "$output" == *$'\e]2;vim\a'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/b-blank-cover-55.ready" ]
}

@test "cover: the scratchpad rule matches only a new cover, so an i3 reload never hides one on screen" {
    mkdir -p "$HOME/.i3rc"
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/blank-screen"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/63-blank-screen.sh" "$copy/basic/"
    cp "$REPO/blank-screen/b-blank" "$copy/blank-screen/"
    run bash "$copy/basic/63-blank-screen.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'for_window \[class="^b-blank-cover\$" title="^b-blank-new\$"\] move scratchpad' \
        "$HOME/.i3rc/10-blank-screen.local"
}

@test "cover: \$mod+z on the cover swaps the window back and closes the cover in one redraw" {
    workspaces "3"
    local tree="$BATS_TEST_TMPDIR/tree.json"
    echo '{"nodes":[{"type":"workspace","name":"3","nodes":[{"id":9,"focused":true,"border":"normal","current_border_width":3,"window_properties":{"class":"b-blank-cover","instance":"b-blank-cover-55"}}]},
        {"type":"workspace","name":"__i3_scratch","nodes":[{"id":7,"marks":["_b-cover-55"],"window_properties":{"class":"Alacritty","instance":"Alacritty"}}]}]}' > "$tree"
    fake_tree "$tree"
    run "$REPO/blank-screen/b-blank" window
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_LOG")" = 'i3-msg [con_id=7] border normal 3; [con_id=7] swap container with con_id 9; [con_id=7] unmark _b-cover-55, focus; [con_id=9] kill' ]
}

@test "cover: a window whose cover is gone comes back tiled" {
    workspaces "3"
    local tree="$BATS_TEST_TMPDIR/tree.json"
    echo '{"type":"workspace","name":"3","nodes":[{"id":7,"focused":true,"marks":["_b-cover-55"],"window_properties":{"class":"Alacritty","instance":"Alacritty"}}]}' > "$tree"
    fake_tree "$tree"
    run "$REPO/blank-screen/b-blank" window
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_LOG")" = 'i3-msg [con_id=7] scratchpad show, floating disable, unmark _b-cover-55' ]
}

@test "cover: the module binds \$mod+z to cover one window" {
    mkdir -p "$HOME/.i3rc"
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/blank-screen"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/63-blank-screen.sh" "$copy/basic/"
    cp "$REPO/blank-screen/b-blank" "$copy/blank-screen/"
    run bash "$copy/basic/63-blank-screen.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'bindsym $mod+z exec --no-startup-id ~/.local/bin/b-blank window' \
        "$HOME/.i3rc/10-blank-screen.local"
}
