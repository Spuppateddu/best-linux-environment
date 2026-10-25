#!/usr/bin/env bats
# basic/77-spreadsheet.sh — installs LibreOffice Calc, makes it the spreadsheet default.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export BLE_PROFILE=desktop
}

@test "77-spreadsheet: Calc is not installed, so apt installs it" {
    fake_cmd xdg-mime 'echo "xdg-mime $*" >> "$FAKE_LOG"'
    run bash "$REPO/basic/77-spreadsheet.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -q 'apt-get install.* libreoffice-calc' "$FAKE_LOG"
}

@test "77-spreadsheet: Calc already the default for every type, so nothing is set" {
    pkg_status libreoffice-calc installed
    fake_cmd xdg-mime '[ "$1" = query ] && echo libreoffice-calc.desktop; echo "xdg-mime $*" >> "$FAKE_LOG"'
    # The real .desktop lives in /usr/share: a dry run skips the file check.
    DRY_RUN=true run bash "$REPO/basic/77-spreadsheet.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"already the system default for every spreadsheet type"* ]]
    ! grep -q 'xdg-mime default' "$FAKE_LOG"
}

@test "77-spreadsheet: a csv still on vim is listed to move to Calc" {
    pkg_status libreoffice-calc installed
    fake_cmd xdg-mime '[ "$1" = query ] && echo ble-vim.desktop; exit 0'
    DRY_RUN=true run bash "$REPO/basic/77-spreadsheet.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"would set:"*libreoffice-calc.desktop*"5 type(s)"*text/csv* ]]
}

@test "77-spreadsheet: server profile installs nothing" {
    export BLE_PROFILE=server
    run bash "$REPO/basic/77-spreadsheet.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q 'apt-get install' "$FAKE_LOG"
}
