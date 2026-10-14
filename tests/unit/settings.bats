#!/usr/bin/env bats
# basic/95-settings.sh, run against a temp settings.local with i3-msg faked.

load helpers

# run_settings LINES...  — settings.local holds LINES; ~/.i3rc includes *.local.
run_settings() {
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/settings.local"
    mkdir -p "$HOME/.i3rc"
    echo 'include ~/.i3rc/*.local' > "$HOME/.i3rc/config"
    fake_cmd i3-msg 'echo "i3-msg $*" >> "$FAKE_LOG"'
    BLE_SETTINGS_LOCAL="$BATS_TEST_TMPDIR/settings.local" \
    BLE_ALIASES_LOCAL="$BATS_TEST_TMPDIR/aliases.local" \
        run bash "$REPO/basic/95-settings.sh" </dev/null
}

@test "95-settings: the split indicator differs from the focused border" {
    # 92 is a dark purple: white text, so a white indicator on a purple border.
    run_settings BLE_I3_BORDER_COLOR=92 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx 'client.focused          #8700d7 #8700d7 #ffffff #ffffff #8700d7' "$HOME/.i3rc/06-colors.local"
}

@test "95-settings: a light border gets a dark split indicator" {
    run_settings BLE_I3_BORDER_COLOR=226 BLE_I3_UNFOCUSED_COLOR=22
    [ "$status" -eq 0 ]
    grep -qx 'client.focused          #ffff00 #ffff00 #1d2021 #1d2021 #ffff00' "$HOME/.i3rc/06-colors.local"
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
