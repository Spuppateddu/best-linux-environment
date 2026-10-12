#!/usr/bin/env bats
# basic/25-idle-poweroff.sh and the BLE_IDLE_POWEROFF switch in settings.local.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export BLE_SYSTEMD_RUN_DIR="$BATS_TEST_TMPDIR/run-systemd"
    export BLE_SETTINGS_LOCAL="$BATS_TEST_TMPDIR/settings.local"
    mkdir -p "$BLE_SYSTEMD_RUN_DIR"
    # The timer is on, autosuspend is absent; every systemctl call is logged.
    fake_cmd systemctl 'echo "systemctl $*" >> "$FAKE_LOG"; [[ "$1" != cat ]]'
    # Log only: nothing may really be written under /usr or /etc.
    fake_cmd sudo '[[ "$1" == -n ]] && shift; echo "sudo $*" >> "$FAKE_LOG"
        [[ "$1" == systemctl || "$1" == true ]] && "$@"; exit 0'
    pkg_status xprintidle installed
}

@test "idle-poweroff: BLE_IDLE_POWEROFF=false stops the timer and installs nothing" {
    echo 'BLE_IDLE_POWEROFF=false' > "$BLE_SETTINGS_LOCAL"
    run bash "$REPO/basic/25-idle-poweroff.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'sudo systemctl disable --now --quiet idle-poweroff.timer' "$FAKE_LOG"
    ! grep -q 'install' "$FAKE_LOG"
    [[ "$output" == *"Automatic poweroff is OFF"* ]]
}

@test "idle-poweroff: BLE_IDLE_POWEROFF=false with the timer already off does nothing" {
    echo 'BLE_IDLE_POWEROFF=no' > "$BLE_SETTINGS_LOCAL"
    fake_cmd systemctl 'echo "systemctl $*" >> "$FAKE_LOG"; [[ "$1" != is-* ]]'
    run bash "$REPO/basic/25-idle-poweroff.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q 'disable' "$FAKE_LOG"
    [[ "$output" == *"already off"* ]]
}

@test "idle-poweroff: true, or no line at all, keeps the timer installed" {
    for line in 'BLE_IDLE_POWEROFF=true' '# nothing'; do
        : > "$FAKE_LOG"
        echo "$line" > "$BLE_SETTINGS_LOCAL"
        run bash "$REPO/basic/25-idle-poweroff.sh" </dev/null
        [ "$status" -eq 0 ]
        ! grep -q 'disable' "$FAKE_LOG"
        grep -q 'sudo install .*/usr/local/sbin/idle-poweroff' "$FAKE_LOG"
    done
}
