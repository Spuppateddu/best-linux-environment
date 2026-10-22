#!/usr/bin/env bats
# The module scripts' --check and --uninstall, with apt and sudo faked.

load helpers

@test "brave --check: installed is yes, removed-with-config (rc) is no" {
    pkg_status brave-browser installed
    run bash "$REPO/advanced/brave.sh" --check
    [ "$status" -eq 0 ]
    : > "$FAKE_DPKG"; pkg_status brave-browser config-files
    run bash "$REPO/advanced/brave.sh" --check
    [ "$status" -eq 1 ]
}

@test "brave --uninstall: removes both packages and the rofi launcher" {
    pkg_status brave-browser installed
    pkg_status brave-keyring installed
    mkdir -p "$HOME/.local/share/applications"
    touch "$HOME/.local/share/applications/brave-browser.desktop"
    run bash "$REPO/advanced/brave.sh" --uninstall
    [ "$status" -eq 0 ]
    grep -qx 'apt-get remove -y brave-browser brave-keyring' "$FAKE_LOG"
    [ ! -e "$HOME/.local/share/applications/brave-browser.desktop" ]
}

@test "brave --uninstall: already removed still clears the launcher" {
    pkg_status brave-browser config-files
    mkdir -p "$HOME/.local/share/applications"
    touch "$HOME/.local/share/applications/brave-browser.desktop"
    run bash "$REPO/advanced/brave.sh" --uninstall
    [ "$status" -eq 0 ]
    ! grep -q apt-get "$FAKE_LOG"
    [ ! -e "$HOME/.local/share/applications/brave-browser.desktop" ]
}

@test "google-chrome --uninstall: removes the package and the rofi launcher" {
    pkg_status google-chrome-stable installed
    mkdir -p "$HOME/.local/share/applications"
    touch "$HOME/.local/share/applications/google-chrome.desktop"
    run bash "$REPO/advanced/google-chrome.sh" --uninstall
    [ "$status" -eq 0 ]
    grep -qx 'apt-get remove -y google-chrome-stable' "$FAKE_LOG"
    [ ! -e "$HOME/.local/share/applications/google-chrome.desktop" ]
}

@test "every --uninstall: a dry run on a machine without the app succeeds" {
    local failed=()
    for s in $(grep -l -- '--uninstall' "$REPO"/advanced/*.sh "$REPO"/basic/*.sh); do
        DRY_RUN=true run bash "$s" --uninstall </dev/null
        [ "$status" -eq 0 ] || failed+=("${s#"$REPO"/} ($status): ${output##*$'\n'}")
    done
    [ ${#failed[@]} -eq 0 ] || { printf '%s\n' "${failed[@]}"; false; }
}

@test "every --check: answers without touching the machine" {
    local failed=()
    for s in $(grep -l -- '--check' "$REPO"/advanced/*.sh "$REPO"/basic/*.sh); do
        run bash "$s" --check </dev/null
        [[ "$status" -eq 0 || "$status" -eq 1 ]] || failed+=("${s#"$REPO"/} ($status)")
    done
    [ ${#failed[@]} -eq 0 ] || { printf '%s\n' "${failed[@]}"; false; }
    # A check must ask, never act: no apt or sudo call at all.
    [ ! -s "$FAKE_LOG" ] || { cat "$FAKE_LOG"; false; }
}

@test "megacmd: a machine with MEGAsync loses it, and gets the boot service" {
    pkg_status megacmd installed
    pkg_status megasync installed
    export BLE_MEGA_SOURCES="$BATS_TEST_TMPDIR/megaio.sources"
    touch "$BLE_MEGA_SOURCES"
    mkdir -p "$HOME/.config/autostart" "$HOME/.local/bin"
    touch "$HOME/.config/autostart/megasync.desktop" "$HOME/.local/bin/megasync-wait-tray"
    fake_cmd systemctl 'exit 1'
    fake_cmd loginctl 'echo yes'
    run bash "$REPO/advanced/megacmd.sh" </dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -qx 'apt-get remove -y megasync' "$FAKE_LOG"
    [ ! -e "$HOME/.config/autostart/megasync.desktop" ]
    [ ! -e "$HOME/.local/bin/megasync-wait-tray" ]
    local unit="$HOME/.config/systemd/user/mega-cmd.service"
    grep -q '^ExecStart=/usr/bin/mega-cmd-server' "$unit"
    [ "$(readlink "$HOME/.config/systemd/user/default.target.wants/mega-cmd.service")" = "$unit" ]
}

@test "megacmd: a re-run with no MEGAsync touches no package" {
    pkg_status megacmd installed
    export BLE_MEGA_SOURCES="$BATS_TEST_TMPDIR/megaio.sources"
    touch "$BLE_MEGA_SOURCES"
    fake_cmd systemctl 'exit 1'
    fake_cmd loginctl 'echo yes'
    run bash "$REPO/advanced/megacmd.sh" </dev/null
    [ "$status" -eq 0 ]
    run bash "$REPO/advanced/megacmd.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q apt-get "$FAKE_LOG"
}

@test "megacmd --uninstall: removes the package and the boot service" {
    pkg_status megacmd installed
    fake_cmd systemctl 'exit 1'
    local dir="$HOME/.config/systemd/user"
    mkdir -p "$dir/default.target.wants"
    touch "$dir/mega-cmd.service"
    ln -s "$dir/mega-cmd.service" "$dir/default.target.wants/mega-cmd.service"
    run bash "$REPO/advanced/megacmd.sh" --uninstall
    [ "$status" -eq 0 ]
    grep -qx 'apt-get remove -y megacmd' "$FAKE_LOG"
    [ ! -e "$dir/mega-cmd.service" ]
    [ ! -L "$dir/default.target.wants/mega-cmd.service" ]
}
