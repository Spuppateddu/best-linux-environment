#!/usr/bin/env bats
# basic/95-settings.sh, run against a temp settings.local with i3-msg faked.

load helpers

# run_settings LINES...  — settings.local holds LINES; ~/.i3rc includes *.local.
# The example is empty unless a test writes one, so nothing is filled in.
run_settings() {
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/settings.local"
    touch "$BATS_TEST_TMPDIR/settings.local.example"
    mkdir -p "$HOME/.i3rc"
    echo 'include ~/.i3rc/*.local' > "$HOME/.i3rc/config"
    fake_cmd i3-msg 'echo "i3-msg $*" >> "$FAKE_LOG"'
    BLE_SETTINGS_LOCAL="$BATS_TEST_TMPDIR/settings.local" \
    BLE_ALIASES_LOCAL="$BATS_TEST_TMPDIR/aliases.local" \
    BLE_SETTINGS_EXAMPLE="$BATS_TEST_TMPDIR/settings.local.example" \
        run bash "$REPO/basic/95-settings.sh" </dev/null
}

@test "95-settings: the split indicator is the border colour, so no edge shows" {
    # 92 is a dark purple: white title text, but the indicator stays purple.
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx 'client.focused          #8700d7 #8700d7 #ffffff #8700d7 #8700d7' "$HOME/.i3rc/06-colors.local"
}

# fake_desktop_mode [BODY]  — a desktop_mode.sh whose flag is the 90- file, as
# the real one; BODY replaces how it switches.
fake_desktop_mode() {
    local body='[ "$1" = tiling ] && touch "$F" || rm -f "$F"'
    mkdir -p "$HOME/.i3rc/scripts"
    cat > "$HOME/.i3rc/scripts/desktop_mode.sh" <<EOS
#!/usr/bin/env bash
F="\$HOME/.i3rc/90-tiling-mode.local"
case "\$1" in
    status) [ -e "\$F" ] && echo tiling || echo floating; exit 0 ;;
esac
echo "desktop_mode \$1" >> "$FAKE_LOG"
${1:-$body}
EOS
    chmod +x "$HOME/.i3rc/scripts/desktop_mode.sh"
}

@test "95-settings: BLE_I3_DESKTOP=tiling switches a floating desktop" {
    fake_desktop_mode
    run_settings BLE_I3_DESKTOP=tiling
    [ "$status" -eq 0 ]
    grep -qx 'desktop_mode tiling' "$FAKE_LOG"
    [ -e "$HOME/.i3rc/90-tiling-mode.local" ]
}

@test "95-settings: BLE_I3_DESKTOP already in place switches nothing" {
    fake_desktop_mode
    touch "$HOME/.i3rc/90-tiling-mode.local"
    run_settings BLE_I3_DESKTOP=tiled
    [ "$status" -eq 0 ]
    ! grep -q 'desktop_mode' "$FAKE_LOG"
}

@test "95-settings: no BLE_I3_DESKTOP leaves the mode to the keybinding" {
    fake_desktop_mode
    touch "$HOME/.i3rc/90-tiling-mode.local"
    run_settings BLE_I3_BAR=all
    [ "$status" -eq 0 ]
    ! grep -q 'desktop_mode' "$FAKE_LOG"
    [ -e "$HOME/.i3rc/90-tiling-mode.local" ]
}

@test "95-settings: a BLE_I3_DESKTOP that is no mode is warned about and ignored" {
    fake_desktop_mode
    run_settings BLE_I3_DESKTOP=stacked
    [ "$status" -eq 0 ]
    [[ "$output" == *"not floating or tiling"* ]]
    ! grep -q 'desktop_mode' "$FAKE_LOG"
}

@test "95-settings: with no i3 running the switch still counts once its flag is written" {
    # The real script writes its files, then dies at `i3-msg reload`.
    fake_desktop_mode 'rm -f "$HOME/.i3rc/90-tiling-mode.local"; exit 1'
    touch "$HOME/.i3rc/90-tiling-mode.local"
    run_settings BLE_I3_DESKTOP=floating
    [ "$status" -eq 0 ]
    [[ "$output" == *"i3 desktop: floating."* ]]
    [ ! -e "$HOME/.i3rc/90-tiling-mode.local" ]
}

@test "95-settings: b-apply re-applies settings, aliases and fonts, and replaces b-alias" {
    mkdir -p "$HOME/.bash"; touch "$HOME/.bash/bashrc"
    run_settings BLE_EDITOR=vim
    [ "$status" -eq 0 ]
    gen="$HOME/.bash/bash-ble.local"
    grep -q '^b-apply() {' "$gen"
    ! grep -q 'b-alias' "$gen"
    for m in 25-idle-poweroff 95-settings 99-font-sizes; do grep -q "basic/$m.sh" "$gen"; done
    bash -n "$gen"
}

# example LINES...  — the settings.local.example run_settings reads.
example() { printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/settings.local.example"; }

@test "95-settings: a key new in the example is added to settings.local, with its comments" {
    example '# ── The i3 desktop' '# How i3 lays out windows.' 'BLE_I3_DESKTOP=floating' '' \
            '# The editor.' 'BLE_EDITOR=vim'
    run_settings BLE_EDITOR=nano
    [ "$status" -eq 0 ]
    f="$BATS_TEST_TMPDIR/settings.local"
    grep -qx '# How i3 lays out windows.' "$f"
    grep -qx 'BLE_I3_DESKTOP=floating' "$f"
    [ "$(grep -c '^BLE_EDITOR=' "$f")" -eq 1 ]
    grep -qx 'BLE_EDITOR=nano' "$f"
}

@test "95-settings: a paragraph with two keys adds only the missing one" {
    example '# The title bars.' 'BLE_I3_TITLEBAR=false' 'BLE_FIREFOX_TITLEBAR=false'
    run_settings BLE_I3_TITLEBAR=true
    [ "$status" -eq 0 ]
    f="$BATS_TEST_TMPDIR/settings.local"
    grep -qx 'BLE_FIREFOX_TITLEBAR=false' "$f"
    [ "$(grep -c '^BLE_I3_TITLEBAR=' "$f")" -eq 1 ]
}

@test "95-settings: a key you commented out is not added back" {
    example 'BLE_I3_DESKTOP=floating'
    run_settings '#BLE_I3_DESKTOP=tiling'
    [ "$status" -eq 0 ]
    ! grep -q '^BLE_I3_DESKTOP' "$BATS_TEST_TMPDIR/settings.local"
}

@test "95-settings: keys commented out in the example are never added" {
    example '#BLE_GIT_NAME=Your Name'
    run_settings BLE_EDITOR=vim
    [ "$status" -eq 0 ]
    ! grep -q 'BLE_GIT_NAME' "$BATS_TEST_TMPDIR/settings.local"
}

@test "95-settings: a second run adds nothing more" {
    example '# The editor.' 'BLE_EDITOR=vim' '' 'BLE_I3_BAR=all'
    run_settings BLE_EDITOR=vim
    f="$BATS_TEST_TMPDIR/settings.local"
    cp "$f" "$BATS_TEST_TMPDIR/after-first"
    BLE_SETTINGS_LOCAL="$f" BLE_ALIASES_LOCAL="$BATS_TEST_TMPDIR/aliases.local" \
    BLE_SETTINGS_EXAMPLE="$BATS_TEST_TMPDIR/settings.local.example" \
        run bash "$REPO/basic/95-settings.sh" </dev/null
    [ "$status" -eq 0 ]
    cmp "$f" "$BATS_TEST_TMPDIR/after-first"
}

@test "95-settings: --dry-run only says what it would add" {
    example 'BLE_I3_BAR=all'
    printf 'BLE_EDITOR=vim\n' > "$BATS_TEST_TMPDIR/settings.local"
    mkdir -p "$HOME/.i3rc"; echo 'include ~/.i3rc/*.local' > "$HOME/.i3rc/config"
    DRY_RUN=true BLE_SETTINGS_LOCAL="$BATS_TEST_TMPDIR/settings.local" \
    BLE_ALIASES_LOCAL="$BATS_TEST_TMPDIR/aliases.local" \
    BLE_SETTINGS_EXAMPLE="$BATS_TEST_TMPDIR/settings.local.example" \
        run bash "$REPO/basic/95-settings.sh" </dev/null
    [[ "$output" == *"would add:"*"BLE_I3_BAR"* ]]
    ! grep -q 'BLE_I3_BAR' "$BATS_TEST_TMPDIR/settings.local"
}

# alacritty_repo  — a ~/.alacritty whose alacritty.toml imports opacity.local.toml.
alacritty_repo() {
    mkdir -p "$HOME/.alacritty"
    printf 'import = ["~/.alacritty/opacity.local.toml"]\n' > "$HOME/.alacritty/alacritty.toml"
}

@test "95-settings: BLE_TERMINAL_OPACITY lands in ~/.alacritty/opacity.local.toml" {
    alacritty_repo
    run_settings BLE_TERMINAL_OPACITY=0.85
    [ "$status" -eq 0 ]
    grep -qx 'opacity = 0.85' "$HOME/.alacritty/opacity.local.toml"
}

@test "95-settings: no BLE_TERMINAL_OPACITY drops the file, so the theme decides" {
    alacritty_repo
    echo 'opacity = 0.5' > "$HOME/.alacritty/opacity.local.toml"
    run_settings BLE_EDITOR=vim
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.alacritty/opacity.local.toml" ]
}

@test "95-settings: a BLE_TERMINAL_OPACITY that is not 0 to 1 is warned about and ignored" {
    alacritty_repo
    run_settings BLE_TERMINAL_OPACITY=85
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a number from 0 to 1"* ]]
    [ ! -e "$HOME/.alacritty/opacity.local.toml" ]
}

@test "95-settings: an alacritty.toml without the import gets a warning, not a file" {
    mkdir -p "$HOME/.alacritty"; echo '[font]' > "$HOME/.alacritty/alacritty.toml"
    run_settings BLE_TERMINAL_OPACITY=0.9
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not load opacity.local.toml"* ]]
    [ ! -e "$HOME/.alacritty/opacity.local.toml" ]
}
