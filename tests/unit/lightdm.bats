#!/usr/bin/env bats
# basic/30-lightdm.sh: the login screen's wallpaper, theme and greeter drop-in.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export BLE_PROFILE=desktop
    pkg_status lightdm installed
    pkg_status lightdm-gtk-greeter installed
    # Log only: the real commands would write under /etc and /usr.
    fake_cmd sudo '[[ "$1" == -n ]] && shift; echo "sudo $*" >> "$FAKE_LOG"'
}

@test "lightdm: the module installs the wallpaper, theme and greeter drop-in" {
    run bash "$REPO/basic/30-lightdm.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx "sudo install -D -m 0644 -o root -g root $REPO/wallpapers/default.jpg /usr/share/backgrounds/ble-login.jpg" "$FAKE_LOG"
    grep -qx "sudo install -D -m 0644 -o root -g root $REPO/login-screen/gtk.css /usr/share/themes/BLE-Retro/gtk-3.0/gtk.css" "$FAKE_LOG"
    grep -qx "sudo install -D -m 0644 -o root -g root $REPO/login-screen/greeter.conf /etc/xdg/lightdm/lightdm-gtk-greeter.conf.d/50-ble.conf" "$FAKE_LOG"
}

@test "lightdm: greeter.conf names the image and theme the module installs" {
    grep -qx 'background=/usr/share/backgrounds/ble-login.jpg' "$REPO/login-screen/greeter.conf"
    grep -qx 'theme-name=BLE-Retro' "$REPO/login-screen/greeter.conf"
}

@test "lightdm: greeter.conf position uses whole percents" {
    # The greeter cannot read 87.5% and drops the box at the top of the screen.
    run grep -E '^position=.*[0-9]\.[0-9]' "$REPO/login-screen/greeter.conf"
    [ "$status" -eq 1 ]
}
