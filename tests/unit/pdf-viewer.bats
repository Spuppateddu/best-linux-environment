#!/usr/bin/env bats
# basic/75-pdf-viewer.sh — installs Okular, points yazi's PDFs and markdown at it.

load helpers

MD_RULE='{ url = "*.{md,markdown}", use = [ "pdf", "edit" ] },'

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export BLE_PROFILE=desktop
    fake_cmd xdg-mime 'echo "xdg-mime $*" >> "$FAKE_LOG"'
    YAZI_TOML="$HOME/.config/yazi/yazi.toml"
}

# Okular installed: a fake binary and the dpkg line apt_ensure looks for.
fake_okular() { fake_cmd okular 'exit 0'; pkg_status okular installed; }

@test "75-pdf-viewer: Okular is not installed, so apt installs it" {
    run bash "$REPO/basic/75-pdf-viewer.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -q 'apt-get install.* okular' "$FAKE_LOG"
}

@test "75-pdf-viewer: a fresh yazi.toml opens PDFs and markdown in Okular" {
    fake_okular
    run bash "$REPO/basic/75-pdf-viewer.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q 'apt-get install' "$FAKE_LOG"
    grep -qF "run = 'okular -- %s'" "$YAZI_TOML"
    grep -qF "$MD_RULE" "$YAZI_TOML"
}

@test "75-pdf-viewer: a yazi.toml from before markdown gets the rule once" {
    fake_okular
    mkdir -p "$(dirname "$YAZI_TOML")"
    printf '%s\n' '[opener]' 'pdf = [' \
        $'\t{ run = \'okular -- %s\', orphan = true, desc = "Okular", for = "unix" },' \
        ']' '' '[open]' 'prepend_rules = [' $'\t{ mime = "application/pdf", use = "pdf" },' ']' \
        > "$YAZI_TOML"
    bash "$REPO/basic/75-pdf-viewer.sh" </dev/null
    run bash "$REPO/basic/75-pdf-viewer.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"already opens markdown in Okular"* ]]
    [ "$(grep -cF "$MD_RULE" "$YAZI_TOML")" -eq 1 ]
    # Right under prepend_rules, so it wins over every later rule.
    grep -A1 '^prepend_rules = \[' "$YAZI_TOML" | grep -qF "$MD_RULE"
}

@test "75-pdf-viewer: a hand-written [open] block gets no markdown rule" {
    fake_okular
    mkdir -p "$(dirname "$YAZI_TOML")"
    printf '%s\n' '[open]' 'rules = [' $'\t{ mime = "application/pdf", use = "pdf" },' ']' > "$YAZI_TOML"
    run bash "$REPO/basic/75-pdf-viewer.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"markdown rule left to you"* ]]
    ! grep -qF "$MD_RULE" "$YAZI_TOML"
}
