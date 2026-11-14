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

@test "keyboard: the TH66 Pro's Fn row media keys type F1-F12 (no F3/F4)" {
    f="$REPO/keyboard/90-ble-epomaker-th66.hwdb"
    for pair in c0070=f1 c006f=f2 c018a=f5 c0194=f6 c00b6=f7 c00cd=f8 \
                c00b5=f9 c00e2=f10 c00ea=f11 c00e9=f12; do
        grep -qx " KEYBOARD_KEY_$pair" "$f"
    done
    # Fn+3/Fn+4 send Win+Tab / Win+E: remapping Tab (7002b) or E (70008) breaks them.
    ! grep -qE 'KEYBOARD_KEY_700(2b|08)=' "$f"
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

@test "keyboard: the hwdb turns off Power, Sleep and Print Screen on the HHKB Hybrid only" {
    f="$REPO/keyboard/90-ble-hhkb-hybrid.hwdb"
    grep -qx 'evdev:input:b0003v04FEp0021\*' "$f"
    grep -qx 'evdev:name:\*HHKB\*:\*' "$f"
    grep -qx ' KEYBOARD_KEY_70066=reserved' "$f"
    grep -qx ' KEYBOARD_KEY_700f8=reserved' "$f"
    grep -qx ' KEYBOARD_KEY_70046=reserved' "$f"
    [ "$(grep -c '^evdev:' "$f")" -eq 2 ]
}

@test "keyboard: no hwdb file has a blank line between its match lines and its key lines" {
    for f in "$REPO"/keyboard/*.hwdb; do
        run awk '/^evdev:/{m=1} m && /^$/{print "blank"} / KEYBOARD_KEY/{m=0}' "$f"
        [ -z "$output" ]
    done
}
