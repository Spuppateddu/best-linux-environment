#!/usr/bin/env bats
# lock-screen/b-lock (i3lock over the login screen's picture) and basic/64-lock-screen.sh.

load helpers

eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
    # The fake i3lock logs its options instead of locking.
    fake_cmd i3lock 'echo "i3lock $*" >> "$FAKE_LOG"'
    fake_cmd xdpyinfo 'echo "  dimensions:    1366x768 pixels (361x203 millimeters)"'
}

# monitors WxH/MMxH/MM+X+Y...  — what the fake xrandr --listmonitors reports.
monitors() {
    export FAKE_MONS="$*"
    fake_cmd xrandr 'echo "Monitors: $#"; i=0; for m in $FAKE_MONS; do echo " $i: +DP-$i $m  DP-$i"; i=$((i+1)); done'
}

@test "lock: one picture spans every monitor and i3lock gets the options it was given" {
    monitors 1366/309x768/173+0+0 800/200x600/150+1366+0
    run "$REPO/lock-screen/b-lock" --nofork
    [ "$status" -eq 0 ]
    png="$(ls "$XDG_CACHE_HOME"/b-lock/*.png)"
    [ "$(cat "$FAKE_LOG")" = "i3lock -c 282828 -i $png --nofork" ]
    [ "$(python3 -c 'import sys; from PIL import Image; print(*Image.open(sys.argv[1]).size)' "$png")" = "2166 768" ]
}

@test "lock: the same monitors reuse the picture already drawn" {
    monitors 1366/309x768/173+0+0
    first="$("$REPO/lock-screen/b-lock" image)"
    touch -d '2000-01-01' "$first"
    [ "$("$REPO/lock-screen/b-lock" image)" = "$first" ]
    [ "$(stat -c %Y "$first")" = "$(date -d '2000-01-01' +%s)" ]
}

@test "lock: a new monitor layout draws a new picture and drops the old one" {
    monitors 1366/309x768/173+0+0
    old="$("$REPO/lock-screen/b-lock" image)"
    monitors 800/200x600/150+0+0
    new="$("$REPO/lock-screen/b-lock" image)"
    [ "$new" != "$old" ]
    [ ! -e "$old" ]
    [ -s "$new" ]
}

@test "lock: no monitors to draw for still locks, on plain gruvbox" {
    fake_cmd xrandr 'exit 1'
    run "$REPO/lock-screen/b-lock" --nofork
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_LOG")" = "i3lock -c 282828 --nofork" ]
}

@test "lock: the module links b-lock into ~/.local/bin" {
    # The repo is mounted read-only and the module chmods the script: run a copy.
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/lock-screen"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/64-lock-screen.sh" "$copy/basic/"
    cp "$REPO/lock-screen/b-lock" "$copy/lock-screen/"
    for p in i3lock python3 python3-pil x11-xserver-utils x11-utils; do pkg_status "$p" installed; done
    run bash "$copy/basic/64-lock-screen.sh" </dev/null
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.local/bin/b-lock")" = "$copy/lock-screen/b-lock" ]
}
