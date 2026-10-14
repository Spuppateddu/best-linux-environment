#!/usr/bin/env bats
# basic/45-glow.sh and the mdv it installs, with glow faked.

load helpers

# A glow that prints its arguments instead of rendering.
fake_glow() { fake_cmd glow 'echo "glow $*"'; }

@test "45-glow: installs mdv, the three styles and a gruvbox glow.yml" {
    fake_glow
    run bash "$REPO/basic/45-glow.sh" </dev/null
    [ "$status" -eq 0 ]
    [ -x "$HOME/.local/bin/mdv" ]
    for s in dark light gruvbox; do [ -f "$HOME/.config/glow/styles/$s.json" ]; done
    grep -qx "style: \"$HOME/.config/glow/styles/gruvbox.json\"" "$HOME/.config/glow/glow.yml"
    ! grep -q apt-get "$FAKE_LOG"
}

@test "45-glow: a second run changes nothing" {
    fake_glow
    bash "$REPO/basic/45-glow.sh" </dev/null
    run bash "$REPO/basic/45-glow.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *installed.* ]]
    [[ "$output" == *"already uses gruvbox"* ]]
}

@test "45-glow: boot keeps an edited glow.yml, setup rewrites it" {
    fake_glow
    mkdir -p "$HOME/.config/glow"
    echo 'style: "dark"' > "$HOME/.config/glow/glow.yml"
    BLE_MODE=boot run bash "$REPO/basic/45-glow.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'style: "dark"' "$HOME/.config/glow/glow.yml"
    BLE_MODE=setup run bash "$REPO/basic/45-glow.sh" </dev/null
    grep -q 'gruvbox.json' "$HOME/.config/glow/glow.yml"
}

@test "45-glow: no glow yet installs it from apt" {
    PATH="$FAKE_BIN:/usr/bin:/bin"
    command -v glow && skip "a real glow in /usr/bin shadows the test"
    run bash "$REPO/basic/45-glow.sh" </dev/null
    grep -q 'apt-get install.* glow' "$FAKE_LOG"
}

@test "mdv: centers a 100-column text in a 200-column terminal" {
    fake_glow
    bash "$REPO/basic/45-glow.sh" </dev/null
    printf '# hi\n\ntext\n' > "$BATS_TEST_TMPDIR/a.md"
    COLUMNS=200 run "$HOME/.local/bin/mdv" "$BATS_TEST_TMPDIR/a.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-p -s $HOME/.cache/mdv/gruvbox-50.json -w 100 "* ]]
    grep -q '"margin": 50' "$HOME/.cache/mdv/gruvbox-50.json"
}

@test "mdv: a wide table widens the column, never past the terminal" {
    fake_glow
    bash "$REPO/basic/45-glow.sh" </dev/null
    { echo '| a | b |'; printf '| %0.s' {1..70}; echo '|'; } > "$BATS_TEST_TMPDIR/t.md"
    COLUMNS=200 run "$HOME/.local/bin/mdv" "$BATS_TEST_TMPDIR/t.md"
    [[ "$output" == *"-w 141 "* ]]
    COLUMNS=120 run "$HOME/.local/bin/mdv" "$BATS_TEST_TMPDIR/t.md"
    [[ "$output" == *"gruvbox-2.json -w 116 "* ]]
}

@test "mdv: an edited style rebuilds the cached copy" {
    fake_glow
    bash "$REPO/basic/45-glow.sh" </dev/null
    printf 'x\n' > "$BATS_TEST_TMPDIR/a.md"
    COLUMNS=200 "$HOME/.local/bin/mdv" "$BATS_TEST_TMPDIR/a.md" >/dev/null
    sleep 1
    sed -i 's/"#ebdbb2"/"#ffffff"/' "$HOME/.config/glow/styles/gruvbox.json"
    COLUMNS=200 "$HOME/.local/bin/mdv" "$BATS_TEST_TMPDIR/a.md" >/dev/null
    grep -q '#ffffff' "$HOME/.cache/mdv/gruvbox-50.json"
}

@test "mdv: an unknown style says so" {
    fake_glow
    bash "$REPO/basic/45-glow.sh" </dev/null
    MDV_STYLE=nope run "$HOME/.local/bin/mdv" "$REPO/README.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no style 'nope'"* ]]
}
