#!/usr/bin/env bats

load helpers

@test "52-alacritty: one scale on every monitor, so a drag to another screen keeps the size" {
    BLE_PROFILE=desktop run bash "$REPO/basic/52-alacritty.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'export WINIT_X11_SCALE_FACTOR=1' "$HOME/.xsessionrc"
    BLE_PROFILE=desktop run bash "$REPO/basic/52-alacritty.sh" </dev/null
    [ "$(grep -c WINIT_X11_SCALE_FACTOR "$HOME/.xsessionrc")" -eq 1 ]
}
