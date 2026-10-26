#!/usr/bin/env bats
# b-idle's named holds, and idle-poweroff honouring them.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export IDLE_POWEROFF_STATE_DIR="$BATS_TEST_TMPDIR/run"
    export IDLE_POWEROFF_BIN="$REPO/idle-poweroff/idle-poweroff.sh"
    HOLDS="$IDLE_POWEROFF_STATE_DIR/holds"
    # What the timer leaves behind on every tick.
    mkdir -p "$HOLDS"; chmod 1777 "$HOLDS"
}

@test "b-idle: off NAME writes a hold without sudo" {
    run bash "$REPO/idle-poweroff/b-idle" off music-scan
    [ "$status" -eq 0 ]
    [ -f "$HOLDS/music-scan" ]
    ! grep -q sudo "$FAKE_LOG"
}

@test "b-idle: off with no name holds as manual" {
    run bash "$REPO/idle-poweroff/b-idle" off
    [ "$status" -eq 0 ]
    [ -f "$HOLDS/manual" ]
}

@test "b-idle: on NAME releases only that hold" {
    bash "$REPO/idle-poweroff/b-idle" off job-a
    bash "$REPO/idle-poweroff/b-idle" off job-b
    run bash "$REPO/idle-poweroff/b-idle" on job-a
    [ "$status" -eq 0 ]
    [ ! -e "$HOLDS/job-a" ]
    [ -f "$HOLDS/job-b" ]
}

@test "b-idle: on with no name releases every hold and the old flag" {
    bash "$REPO/idle-poweroff/b-idle" off job-a
    bash "$REPO/idle-poweroff/b-idle" off job-b
    touch "$IDLE_POWEROFF_STATE_DIR/disabled"
    run bash "$REPO/idle-poweroff/b-idle" on
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$HOLDS")" ]
    [ ! -e "$IDLE_POWEROFF_STATE_DIR/disabled" ]
}

@test "b-idle: a name that is a path is refused" {
    for bad in ../etc a/b .. 'with space'; do
        run bash "$REPO/idle-poweroff/b-idle" off "$bad"
        [ "$status" -ne 0 ]
    done
    [ -z "$(ls -A "$HOLDS")" ]
}

@test "b-idle: holds lists each hold" {
    bash "$REPO/idle-poweroff/b-idle" off job-a
    run bash "$REPO/idle-poweroff/b-idle" holds
    [[ "$output" == *"job-a"*"since"* ]]
    rm -f "$HOLDS/job-a"
    run bash "$REPO/idle-poweroff/b-idle" holds
    [[ "$output" == "no holds" ]]
}

@test "b-idle: without the holds directory, off makes it through sudo" {
    rmdir "$HOLDS"
    run bash "$REPO/idle-poweroff/b-idle" off job-a
    [ "$status" -eq 0 ]
    grep -q "sudo mkdir -p $HOLDS" "$FAKE_LOG"
    [ -f "$HOLDS/job-a" ]
}

@test "idle-poweroff: a hold keeps the machine up" {
    bash "$REPO/idle-poweroff/b-idle" off job-a
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" == *"in use — held until reboot or b-idle on (job-a)"* ]]
}

@test "idle-poweroff: a symlink in the holds directory is not a hold" {
    ln -s /etc/passwd "$HOLDS/sneaky"
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" != *"sneaky"* ]]
}
