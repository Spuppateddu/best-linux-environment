#!/usr/bin/env bats
# basic/50-fonts-cursor.sh — the Cascadia default rule, and the PDF viewers' exception.

load helpers

# Run the module on a desktop where Cascadia is already on disk: nothing to download.
run_fonts() {
    export BLE_PROFILE=desktop
    for p in fontconfig x11-xserver-utils fonts-noto-color-emoji fonts-noto-core; do pkg_status "$p" installed; done
    mkdir -p "$HOME/.local/share/fonts"
    touch "$HOME/.local/share/fonts/CascadiaCodeNF-Regular.ttf"
    fake_cmd fc-cache 'exit 0'
    fake_cmd gsettings 'exit 0'
    fake_cmd curl 'exit 1'
    run bash "$REPO/basic/50-fonts-cursor.sh" </dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    CONF="$HOME/.config/fontconfig/conf.d/60-cascadia-default.conf"
}

# The <match> block that holds LINE, as one string.
block_with() { awk -v l="$1" '/<match/{b=""} {b=b $0 "\n"} /<\/match>/{if (index(b, l)) printf "%s", b}' "$CONF"; }

@test "fonts: every program but the PDF viewers gets Cascadia over Arial" {
    run_fonts
    local main
    main="$(block_with '<test name="prgname" compare="not_eq" qual="all"><string>okular</string>')"
    [ -n "$main" ]
    ! grep -q '<string>Arial</string>' <<<"$main"
    grep -q 'mode="prepend_first" binding="strong"' <<<"$main"
}

@test "fonts: a PDF viewer lets the PDF standard fonts reach their own metric font" {
    run_fonts
    local app viewer
    for app in okular xournalpp evince zathura; do
        viewer="$(block_with "<test name=\"prgname\" compare=\"eq\" qual=\"all\"><string>$app</string>")"
        [ -n "$viewer" ] || { echo "no rule for $app"; false; }
        grep -q 'compare="not_eq" qual="all"><string>Helvetica</string>' <<<"$viewer"
        grep -q 'compare="not_eq" qual="all"><string>Times New Roman</string>' <<<"$viewer"
        grep -q 'mode="prepend_first" binding="strong"' <<<"$viewer"
    done
}
