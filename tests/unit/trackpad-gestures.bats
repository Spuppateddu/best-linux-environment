#!/usr/bin/env bats
# trackpad/ble-trackpad-gestures — the pinch half: nsxiv zooms, nothing else does.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    # The focused window's class comes from $FOCUSED; every key lands in the log.
    fake_cmd xdotool '[[ "$1" == getactivewindow ]] && { echo 42; exit 0; }; echo "xdotool $*" >> "$FAKE_LOG"'
    fake_cmd xprop '[[ "$*" == *_NET_WM_NAME* ]] && { echo "_NET_WM_NAME = \"${TITLE:-}\""; exit 0; }
        echo "WM_CLASS(STRING) = \"$FOCUSED\", \"$FOCUSED\""'
    source "$REPO/trackpad/ble-trackpad-gestures"
}

# pinch SCALE...  — one pinch, as libinput debug-events prints it.
pinch() {
    local t=$'\t' s
    echo " event9   GESTURE_PINCH_BEGIN          +1.000s${t}2"
    for s in "$@"; do
        printf ' event9   GESTURE_PINCH_UPDATE         +1.100s%s2  0.00/ 0.00 ( 0.00/ 0.00 unaccelerated) %5.2f @  0.00\n' "$t" "$s"
    done
    echo " event9   GESTURE_PINCH_END            +1.200s${t}2"
}

@test "gestures: spreading two fingers in nsxiv zooms in, one step per quarter" {
    export FOCUSED=nsxiv
    gestures < <(pinch 1.10 1.30 1.60)
    [ "$(grep -c '^xdotool key plus$' "$FAKE_LOG")" -eq 2 ]
    ! grep -q minus "$FAKE_LOG"
}

@test "gestures: closing two fingers in nsxiv zooms out" {
    export FOCUSED=nsxiv
    gestures < <(pinch 0.90 0.70)
    [ "$(grep -c '^xdotool key minus$' "$FAKE_LOG")" -eq 1 ]
    ! grep -q plus "$FAKE_LOG"
}

@test "gestures: closing two fingers on nsxiv's starting view sends nothing" {
    export FOCUSED=nsxiv TITLE="nsxiv - a.jpg | 3000x2000 42% [start] [1/3]"
    gestures < <(pinch 0.70 0.40)
    ! grep -q 'xdotool key' "$FAKE_LOG"
}

@test "gestures: a pinch in Firefox sends nothing, it zooms by itself" {
    export FOCUSED=firefox
    gestures < <(pinch 1.50 2.00)
    ! grep -q 'xdotool key' "$FAKE_LOG"
}

@test "gestures: a scale of 0 does not loop forever" {
    export FOCUSED=nsxiv
    timeout 5 bash -c "source '$REPO/trackpad/ble-trackpad-gestures'; gestures" < <(pinch 0.00)
}
