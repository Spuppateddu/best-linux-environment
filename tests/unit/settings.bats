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
    BLE_PROFILE="${BLE_PROFILE:-desktop}" \
        run bash "$REPO/basic/95-settings.sh" </dev/null
}

@test "95-settings: the split indicator is the border colour, so no edge shows" {
    # 92 is a dark purple: white title text, but the indicator stays purple.
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx 'client.focused          #8700d7 #8700d7 #ffffff #8700d7 #8700d7' "$HOME/.i3rc/06-colors.local"
}

@test "95-settings: tmux's list highlight takes i3's focused colour" {
    mkdir -p "$HOME/.tmuxrc"
    echo 'source-file -q "$HOME/.tmuxrc/colors.local.conf"' > "$HOME/.tmuxrc/config"
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx 'set -g mode-style "bg=#8700d7,fg=#ffffff"' "$HOME/.tmuxrc/colors.local.conf"
}

@test "95-settings: tmux's current window and pane take i3's focused colour" {
    mkdir -p "$HOME/.tmuxrc"
    echo 'source-file -q "$HOME/.tmuxrc/colors.local.conf"' > "$HOME/.tmuxrc/config"
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx 'set -g window-status-current-format "#\[fg=#ffffff\]#\[bg=#8700d7\] #I#{?#{@name_hidden},, #W} "' \
        "$HOME/.tmuxrc/colors.local.conf"
    grep -qx "set -g pane-active-border-style 'fg=#8700d7,bold'" "$HOME/.tmuxrc/colors.local.conf"
}

@test "95-settings: tmux's session name takes i3's unfocused colour, the focused one under prefix" {
    mkdir -p "$HOME/.tmuxrc"
    echo 'source-file -q "$HOME/.tmuxrc/colors.local.conf"' > "$HOME/.tmuxrc/config"
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qF 'status-left "#[bg=#005f00]#[fg=#ffffff]#{?client_prefix,#[bg=#8700d7]#[fg=#ffffff],} ' \
        "$HOME/.tmuxrc/colors.local.conf"
}

@test "95-settings: a server rolls the i3 colours too, so tmux is coloured" {
    mkdir -p "$HOME/.tmuxrc"
    echo 'source-file -q "$HOME/.tmuxrc/colors.local.conf"' > "$HOME/.tmuxrc/config"
    BLE_PROFILE=server run_settings BLE_PROMPT_COLOR_USER=39
    [ "$status" -eq 0 ]
    grep -q '^BLE_I3_BORDER_COLOR=' "$BATS_TEST_TMPDIR/settings.local"
    grep -q '^BLE_I3_UNFOCUSED_COLOR=' "$BATS_TEST_TMPDIR/settings.local"
    grep -q '^set -g mode-style "bg=#' "$HOME/.tmuxrc/colors.local.conf"
    grep -qF '#{?client_prefix,#[bg=#' "$HOME/.tmuxrc/colors.local.conf"
}

@test "95-settings: a #rrggbb colour lands as is in i3 and tmux" {
    mkdir -p "$HOME/.tmuxrc"
    echo 'source-file -q "$HOME/.tmuxrc/colors.local.conf"' > "$HOME/.tmuxrc/config"
    run_settings BLE_I3_BORDER_COLOR=#0F3D7C BLE_I3_UNFOCUSED_COLOR=178
    [ "$status" -eq 0 ]
    grep -qx 'client.focused          #0f3d7c #0f3d7c #ffffff #0f3d7c #0f3d7c' "$HOME/.i3rc/06-colors.local"
    grep -qx 'set -g mode-style "bg=#0f3d7c,fg=#ffffff"' "$HOME/.tmuxrc/colors.local.conf"
    # Set by hand, so nothing is rolled over it.
    [ "$(grep -c '^BLE_I3_BORDER_COLOR=' "$BATS_TEST_TMPDIR/settings.local")" -eq 1 ]
}

@test "95-settings: a #rrggbb cursor lands as is, with readable text on it" {
    mkdir -p "$HOME/.alacritty"
    printf 'import = ["~/.alacritty/colors.local.toml"]\n' > "$HOME/.alacritty/alacritty.toml"
    run_settings BLE_CURSOR_COLOR=#0f3d7c
    [ "$status" -eq 0 ]
    grep -qx "cursor = '0x0f3d7c'" "$HOME/.alacritty/colors.local.toml"
    grep -qx "text = '0xffffff'" "$HOME/.alacritty/colors.local.toml"
}

@test "95-settings: a #rrggbb prompt is exact on truecolor, the nearest 256 elsewhere" {
    mkdir -p "$HOME/.bash" "$HOME/.zsh"; touch "$HOME/.bash/bashrc" "$HOME/.zsh/zshrc"
    run_settings BLE_PROMPT_COLOR_USER=#0f3d7c BLE_PROMPT_COLOR_PATH=178
    [ "$status" -eq 0 ]
    b="$HOME/.bash/bash-ble.local"; z="$HOME/.zsh/zsh-ble.local"
    grep -qF '\033[1;38;2;15;61;124m\]\u@\h' "$b"
    grep -qF '\033[1;38;5;24m\]\u@\h' "$b"     # #0f3d7c's nearest of the 256
    grep -qF '\033[1;38;5;178m\]\w' "$b"        # a number is the same either way
    grep -qF "uc='#0f3d7c'; pc='178'" "$z"
    grep -qF "uc='24'; pc='178'" "$z"
    bash -n "$b"
}

@test "95-settings: a colour that is neither 0-255 nor #rrggbb is warned about and rolled" {
    run_settings BLE_CURSOR_COLOR=#12345
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a number 0-255 or a #rrggbb colour"* ]]
    grep -q '^BLE_CURSOR_COLOR=[0-9]' "$BATS_TEST_TMPDIR/settings.local"
}

@test "95-settings: a number and the hex it paints count as the same colour" {
    # 24 paints #005f87: the two prompt colours would be one.
    run_settings BLE_PROMPT_COLOR_USER=24 BLE_PROMPT_COLOR_PATH=#005f87
    [ "$status" -eq 0 ]
    [[ "$output" == *"they must differ"* ]]
    [ "$(grep '^BLE_PROMPT_COLOR_PATH=' "$BATS_TEST_TMPDIR/settings.local" | tail -1)" != 'BLE_PROMPT_COLOR_PATH=#005f87' ]
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

# eww_repo  — a ~/.i3rc/eww whose eww.scss imports color.local.scss and focus.local.scss.
eww_repo() {
    mkdir -p "$HOME/.i3rc/eww"
    printf '@import "color.local.scss";\n@import "focus.local.scss";\n' > "$HOME/.i3rc/eww/eww.scss"
}

@test "95-settings: BLE_BAR_COLOR=#rrggbb paints the top bar" {
    eww_repo
    run_settings 'BLE_BAR_COLOR=#3C3836'
    [ "$status" -eq 0 ]
    grep -qx '.bar { background: rgba(60, 56, 54, 0.94); }' "$HOME/.i3rc/eww/color.local.scss"
}

@test "95-settings: BLE_BAR_COLOR=wallpaper leaves the bar following the wallpaper" {
    eww_repo
    run_settings BLE_BAR_COLOR=auto
    [ "$status" -eq 0 ]
    grep -qx '// mode: wallpaper' "$HOME/.i3rc/eww/color.local.scss"
}

@test "95-settings: no BLE_BAR_COLOR leaves an empty import, so eww.scss decides" {
    eww_repo
    echo '.bar { background: red; }' > "$HOME/.i3rc/eww/color.local.scss"
    run_settings BLE_EDITOR=vim
    [ "$status" -eq 0 ]
    ! grep -q 'background' "$HOME/.i3rc/eww/color.local.scss"
}

@test "95-settings: a BLE_BAR_COLOR that is not a colour is warned about and ignored" {
    eww_repo
    run_settings BLE_BAR_COLOR=red
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not wallpaper or a #rrggbb colour"* ]]
    ! grep -q 'background' "$HOME/.i3rc/eww/color.local.scss"
}

@test "95-settings: the bar's current workspace takes i3's focused colour" {
    eww_repo
    run_settings 'BLE_I3_BORDER_COLOR=#0F3D7C' BLE_I3_UNFOCUSED_COLOR=178
    [ "$status" -eq 0 ]
    grep -qx '.ws.focused { background: #0f3d7c; color: #ffffff; }' "$HOME/.i3rc/eww/focus.local.scss"
}

@test "95-settings: a new focused colour reloads the running bar, the same one does not" {
    eww_repo
    export DISPLAY=:0
    fake_cmd eww 'echo "eww $*" >> "$FAKE_LOG"'
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx "eww -c $HOME/.i3rc/eww reload" "$FAKE_LOG"
    : > "$FAKE_LOG"
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    ! grep -q '^eww' "$FAKE_LOG"
}

@test "95-settings: an i3 repo with no focus.local.scss import gets no file, only a warning" {
    mkdir -p "$HOME/.i3rc/eww"
    printf '@import "color.local.scss";\n' > "$HOME/.i3rc/eww/eww.scss"
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not load focus.local.scss"* ]]
    [ ! -e "$HOME/.i3rc/eww/focus.local.scss" ]
}

# fake_xinput  — one touchpad (id 11) and one mouse (id 12); set-prop is logged.
fake_xinput() {
    export BLE_XORG_CONF_DIR="$BATS_TEST_TMPDIR/xorg.conf.d" DISPLAY=:0 BLE_PROFILE=desktop
    fake_cmd xinput 'case "$1" in
        list) printf "11\n12\n" ;;
        list-props) [ "$2" = 11 ] && echo "libinput Tapping Enabled (300): 1"; echo "libinput Accel Speed (301): 0.0" ;;
        set-prop) echo "xinput $*" >> "$FAKE_LOG" ;;
    esac'
}

@test "95-settings: BLE_TRACKPAD_SPEED lands in xorg.conf.d and on the touchpad now" {
    fake_xinput
    run_settings BLE_TRACKPAD_SPEED=0.4
    [ "$status" -eq 0 ]
    grep -q 'Option          "AccelSpeed" "0.4"' "$BLE_XORG_CONF_DIR/60-ble-trackpad-speed.conf"
    grep -qx 'xinput set-prop 11 libinput Accel Speed 0.4' "$FAKE_LOG"
    ! grep -q 'set-prop 12' "$FAKE_LOG"
}

@test "95-settings: the same BLE_TRACKPAD_SPEED again does not touch the root file" {
    fake_xinput
    run_settings BLE_TRACKPAD_SPEED=-0.5
    : > "$FAKE_LOG"
    run_settings BLE_TRACKPAD_SPEED=-0.5
    [ "$status" -eq 0 ]
    [[ "$output" == *"Trackpad speed already -0.5"* ]]
    ! grep -q '^sudo install' "$FAKE_LOG"
}

@test "95-settings: no BLE_TRACKPAD_SPEED drops the file and puts the default back" {
    fake_xinput
    run_settings BLE_TRACKPAD_SPEED=1
    : > "$FAKE_LOG"
    run_settings BLE_EDITOR=vim
    [ "$status" -eq 0 ]
    [ ! -e "$BLE_XORG_CONF_DIR/60-ble-trackpad-speed.conf" ]
    grep -qx 'xinput set-prop 11 libinput Accel Speed 0' "$FAKE_LOG"
}

@test "95-settings: a BLE_TRACKPAD_SPEED that is not -1 to 1 is warned about and ignored" {
    fake_xinput
    run_settings BLE_TRACKPAD_SPEED=5
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a number from -1 to 1"* ]]
    [ ! -e "$BLE_XORG_CONF_DIR/60-ble-trackpad-speed.conf" ]
    ! grep -q 'set-prop' "$FAKE_LOG"
}

@test "95-settings: a desktop without xinput gets it installed" {
    export BLE_XORG_CONF_DIR="$BATS_TEST_TMPDIR/xorg.conf.d" BLE_PROFILE=desktop
    run_settings BLE_TRACKPAD_SPEED=0.2
    [ "$status" -eq 0 ]
    grep -q 'apt-get install -y xinput' "$FAKE_LOG"
}

@test "95-settings: a server sets no trackpad speed and installs nothing for it" {
    export BLE_XORG_CONF_DIR="$BATS_TEST_TMPDIR/xorg.conf.d" BLE_PROFILE=server
    run_settings BLE_TRACKPAD_SPEED=0.2
    [ "$status" -eq 0 ]
    [ ! -e "$BLE_XORG_CONF_DIR/60-ble-trackpad-speed.conf" ]
    ! grep -q 'xinput' "$FAKE_LOG"
}
