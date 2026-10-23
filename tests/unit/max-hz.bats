#!/usr/bin/env bats
# max-hz/b-max-hz and the i3 line basic/80-arandr.sh writes for it.

load helpers

# What `xrandr --query` printed on a PC with one monitor on at 59.98 Hz (it can do
# 74.99) and one plugged in but off.
XRANDR_QUERY='Screen 0: minimum 8 x 8, current 2560 x 1080, maximum 32767 x 32767
HDMI-0 disconnected (normal left inverted right x axis y axis)
DP-2 connected (normal left inverted right x axis y axis)
   3440x1440     59.97 + 100.00
   1920x1080     60.00    59.94    50.00
DP-4 connected primary 2560x1080+0+0 (normal left inverted right x axis y axis) 797mm x 334mm
   2560x1080     59.98*+  74.99    59.94    50.00
   1920x1080     60.00    59.94    50.00
   1280x1024     75.02    60.02
DP-5 disconnected (normal left inverted right x axis y axis)'

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export XRANDR_QUERY
    # --query prints the screen; anything else is a change, logged.
    fake_cmd xrandr '[[ "$1" == --query ]] && { printf "%s\n" "$XRANDR_QUERY"; exit 0; }
        echo "xrandr $*" >> "$FAKE_LOG"'
}

@test "max-hz: a monitor at 60 Hz goes to its highest rate, same resolution" {
    run "$REPO/max-hz/b-max-hz"
    [ "$status" -eq 0 ]
    grep -qx 'xrandr --output DP-4 --mode 2560x1080 --rate 74.99' "$FAKE_LOG"
    [[ "$output" == *"DP-4: 2560x1080 59.98 → 74.99 Hz"* ]]
}

@test "max-hz: a monitor that is off stays off" {
    run "$REPO/max-hz/b-max-hz"
    [ "$status" -eq 0 ]
    ! grep -q 'DP-2' "$FAKE_LOG"
}

@test "max-hz: rates of another resolution do not count" {
    # 1280x1024 offers 75.02, more than 74.99, but it is not the current mode.
    run "$REPO/max-hz/b-max-hz"
    ! grep -q '75.02' "$FAKE_LOG"
}

@test "max-hz: a monitor already at its highest rate is left alone" {
    XRANDR_QUERY="${XRANDR_QUERY/59.98\*+  74.99/59.98 +  74.99*}"
    run "$REPO/max-hz/b-max-hz"
    [ "$status" -eq 0 ]
    [ ! -s "$FAKE_LOG" ]
    [[ "$output" == *"DP-4: 2560x1080 already at 74.99 Hz"* ]]
}

@test "max-hz: no monitor on stops with an error" {
    XRANDR_QUERY='Screen 0: minimum 8 x 8
DP-2 connected (normal left inverted right x axis y axis)
   3440x1440     59.97 + 100.00'
    run "$REPO/max-hz/b-max-hz"
    [ "$status" -eq 1 ]
}

@test "max-hz: the arandr module runs b-max-hz at every i3 login" {
    mkdir -p "$HOME/.i3rc"
    pkg_status arandr installed
    # The repo is mounted read-only and the module chmods the script: run a copy.
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/max-hz"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/80-arandr.sh" "$copy/basic/"
    cp "$REPO/max-hz/b-max-hz" "$copy/max-hz/"
    BLE_PROFILE=desktop run bash "$copy/basic/80-arandr.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'exec_always --no-startup-id ~/.local/bin/b-max-hz' "$HOME/.i3rc/11-max-hz.local"
    [ -L "$HOME/.local/bin/b-max-hz" ]
}
