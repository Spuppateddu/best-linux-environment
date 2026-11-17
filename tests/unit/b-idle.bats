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
    [[ "$output" == *"job-a"*"left, made"* ]]
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
    bash "$REPO/idle-poweroff/b-idle" keep job-a
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" == *"in use — held by b-idle keep for 2h 59m more (job-a)"* ]] \
        || [[ "$output" == *"in use — held by b-idle keep for 3h 00m more (job-a)"* ]]
}

@test "idle-poweroff: a hold older than 3 h no longer keeps the machine up" {
    bash "$REPO/idle-poweroff/b-idle" keep job-a
    touch -d '-181 minutes' "$HOLDS/job-a"
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" != *"held by"* ]]
}

@test "idle-poweroff: a hold dated in the future is not trusted" {
    bash "$REPO/idle-poweroff/b-idle" keep job-a
    touch -d '+1 day' "$HOLDS/job-a"
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" != *"held by"* ]]
}

@test "idle-poweroff: the old disabled flag also ends after 3 h" {
    touch "$IDLE_POWEROFF_STATE_DIR/disabled"
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" == *"held by b-idle keep"*"(disabled)"* ]]
    touch -d '-4 hours' "$IDLE_POWEROFF_STATE_DIR/disabled"
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" != *"held by"* ]]
}

@test "b-idle: keep again resets to 3 h from now, it never adds up" {
    bash "$REPO/idle-poweroff/b-idle" keep job-a
    touch -d '-2 hours' "$HOLDS/job-a"
    run bash "$REPO/idle-poweroff/b-idle" keep job-a
    [ "$status" -eq 0 ]
    age=$(( $(date +%s) - $(stat -c %Y "$HOLDS/job-a") ))
    [ "$age" -ge 0 ] && [ "$age" -lt 5 ]
    run bash "$REPO/idle-poweroff/b-idle" holds
    [[ "$output" == *"job-a"*"2h 59m left"* ]] || [[ "$output" == *"job-a"*"3h 00m left"* ]]
}

@test "b-idle: off is the old name of keep, and it expires too" {
    run bash "$REPO/idle-poweroff/b-idle" off job-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"kept up by job-a until"* ]]
    touch -d '-4 hours' "$HOLDS/job-a"
    run bash "$REPO/idle-poweroff/b-idle" holds
    [[ "$output" == "no holds" ]]
}

@test "b-idle: HOLD_MINUTES from the config sets the length" {
    printf 'HOLD_MINUTES=30\n' > "$BATS_TEST_TMPDIR/idle.conf"
    export IDLE_POWEROFF_CONF="$BATS_TEST_TMPDIR/idle.conf"
    run bash "$REPO/idle-poweroff/b-idle" keep job-a
    [[ "$output" == *"(30m 00s from now)"* ]]
}

@test "idle-poweroff: a symlink in the holds directory is not a hold" {
    ln -s /etc/passwd "$HOLDS/sneaky"
    run bash "$IDLE_POWEROFF_BIN" --status
    [[ "$output" != *"sneaky"* ]]
}
