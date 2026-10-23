#!/usr/bin/env bats
# image-viewer/b-images (one image opens its folder) and basic/57-image-viewer.sh.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export BLE_PROFILE=desktop
    # The fake prints its args, then the -0 names it got on stdin, one per line.
    fake_cmd nsxiv 'echo "nsxiv $*" >> "$FAKE_LOG"; [[ " $* " == *" -i "* ]] && tr "\0" "\n" >> "$FAKE_LOG"; exit 0'
    fake_cmd xdg-mime 'echo "xdg-mime $*" >> "$FAKE_LOG"'
    IMG="$BATS_TEST_TMPDIR/photos"
    mkdir -p "$IMG"
    touch "$IMG/a.jpg" "$IMG/b 2.PNG" "$IMG/c.webp" "$IMG/notes.txt" "$IMG/.hidden.jpg"
    YAZI_TOML="$HOME/.config/yazi/yazi.toml"
}

@test "b-images: one image opens every image in its folder, starting at it" {
    run "$REPO/image-viewer/b-images" "$IMG/b 2.PNG"
    [ "$status" -eq 0 ]
    grep -qx 'nsxiv -a -0 -i -n 2' "$FAKE_LOG"
    [ "$(grep -c "^$IMG/" "$FAKE_LOG")" -eq 3 ]
    ! grep -q 'notes.txt\|\.hidden' "$FAKE_LOG"
}

@test "b-images: several files open as given, no folder" {
    run "$REPO/image-viewer/b-images" -- "$IMG/c.webp" "$IMG/a.jpg"
    [ "$status" -eq 0 ]
    grep -qxF "nsxiv -a -- $IMG/c.webp $IMG/a.jpg" "$FAKE_LOG"
}

@test "b-images: a file that is not an image type opens alone" {
    run "$REPO/image-viewer/b-images" "$IMG/notes.txt"
    [ "$status" -eq 0 ]
    grep -qxF "nsxiv -a -- $IMG/notes.txt" "$FAKE_LOG"
}

@test "57-image-viewer: yazi's old plain nsxiv opener is moved to b-images" {
    pkg_status nsxiv installed; pkg_status libheif-plugin-libde265 installed
    mkdir -p "$(dirname "$YAZI_TOML")" "$HOME/.i3rc"
    printf '%s\n' '[opener]' 'image = [' \
        $'\t{ run = \'nsxiv -a -- %s\', orphan = true, desc = "nsxiv", for = "unix" },' ']' \
        > "$YAZI_TOML"
    # The repo is mounted read-only and the module chmods the script: run a copy.
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/image-viewer"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/57-image-viewer.sh" "$copy/basic/"
    cp "$REPO/image-viewer/b-images" "$copy/image-viewer/"
    run bash "$copy/basic/57-image-viewer.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qF "run = '~/.local/bin/b-images -- %s'" "$YAZI_TOML"
    ! grep -qF "run = 'nsxiv" "$YAZI_TOML"
    [ "$(readlink "$HOME/.local/bin/b-images")" = "$copy/image-viewer/b-images" ]
}

@test "57-image-viewer: nsxiv gets the terminal's 3px border, no title bar" {
    pkg_status nsxiv installed; pkg_status libheif-plugin-libde265 installed
    mkdir -p "$HOME/.i3rc"
    echo 'include ~/.i3rc/*.local' > "$HOME/.i3rc/config"
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/image-viewer"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/57-image-viewer.sh" "$copy/basic/"
    cp "$REPO/image-viewer/b-images" "$copy/image-viewer/"
    run bash "$copy/basic/57-image-viewer.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qxF 'for_window [class="(?i)^nsxiv$"] border pixel 3' "$HOME/.i3rc/07-image-viewer.local"
}
