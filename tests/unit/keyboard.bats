#!/usr/bin/env bats
# advanced/keyboard.sh + keyboard/ — the TH66 Pro's Left Ctrl types ` and ~.

load helpers

@test "keyboard: the hwdb maps Left Ctrl (HID 700e0) to grave on the TH66 Pro only" {
    f="$REPO/keyboard/90-ble-epomaker-th66.hwdb"
    grep -qx 'evdev:input:b0003v3151p4010\*' "$f"
    grep -qx 'evdev:name:\*TH66\*:\*' "$f"
    grep -qx ' KEYBOARD_KEY_700e0=grave' "$f"
    # Every match line is a TH66 one: no other keyboard is touched.
    [ "$(grep -c '^evdev:' "$f")" -eq 2 ]
}

@test "keyboard: the hwdb has no blank line between its match lines and its key line" {
    # A blank line ends a hwdb record: the key would then match nothing.
    run awk '/^evdev:/{m=1} m && /^$/{print "blank"} / KEYBOARD_KEY/{m=0}' "$REPO/keyboard/90-ble-epomaker-th66.hwdb"
    [ -z "$output" ]
}

@test "keyboard: --check fails while the hwdb file is not installed" {
    run bash "$REPO/advanced/keyboard.sh" --check
    [ "$status" -ne 0 ]
}

@test "keyboard: the module is a necessary desktop entry in modules.conf" {
    grep -q '^necessary|keyboard|gui|script|run:advanced/keyboard.sh|' "$REPO/modules.conf"
}
