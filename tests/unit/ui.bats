#!/usr/bin/env bats
# lib/ui.sh — the lists, with no terminal and with a BLE_ANSWERS file.

load helpers

# Three rows, the middle one ticked by default.
LIST='chk_reset; chk_add "Brave — browser" 0; chk_add "Docker Engine" 1; chk_add "Steam — games" 0'

answers() { export BLE_ANSWERS="$BATS_TEST_TMPDIR/answers"; printf '%s\n' "$@" > "$BLE_ANSWERS"; }

@test "checklist: no terminal and no answers keeps the defaults" {
    ble "$LIST; checklist 'Secondary — extra applications' </dev/null; chk_picked"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = 1 ]
}

@test "checklist: answers tick the matching rows and untick the rest" {
    answers '# comment' 'Secondary* | Brave*' 'Secondary* | Steam*'
    ble "$LIST; checklist 'Secondary — extra applications'; chk_picked | paste -sd,"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = 0,2 ]
}

@test "checklist: '-' ticks nothing" {
    answers 'Secondary* | -'
    ble "$LIST; checklist 'Secondary — extra applications'; echo \"count=\$(chk_count)\""
    [ "${lines[-1]}" = count=0 ]
}

@test "checklist: a question the file does not answer keeps its defaults" {
    answers 'Something else | Brave*'
    ble "$LIST; checklist 'Secondary — extra applications'; chk_picked"
    [ "${lines[-1]}" = 1 ]
}

@test "checklist: an answer matching no row stops the run" {
    answers 'Secondary* | Firefox*'
    ble "$LIST; checklist 'Secondary — extra applications'; echo reached"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'Firefox*' matches no row"* ]]
    [[ "$output" != *reached* ]]
}

@test "checklist: a missing answers file stops the run" {
    export BLE_ANSWERS="$BATS_TEST_TMPDIR/nope"
    ble "$LIST; checklist 'Secondary'"
    [ "$status" -eq 1 ]
}

@test "radiolist: the answer picks exactly one row" {
    answers 'Which shell* | bash*'
    ble 'chk_reset; chk_add "zsh — x" 1; chk_add "bash — y" 0; radiolist "Which shell does this machine log in with?"; chk_picked'
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = 1 ]
}

@test "radiolist: an answer of none stops the run" {
    answers 'Which shell* | -'
    ble 'chk_reset; chk_add "zsh" 1; chk_add "bash" 0; radiolist "Which shell?"'
    [ "$status" -eq 1 ]
}

@test "radiolist: no terminal keeps the default, and there is always one" {
    ble 'chk_reset; chk_add "a" 0; chk_add "b" 0; radiolist "Pick" </dev/null; chk_picked'
    [ "${lines[-1]}" = 0 ]
}
