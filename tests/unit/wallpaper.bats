#!/usr/bin/env bats
# wallpapers/b-wallpaper (the `auto` loop), its gitignore rules and basic/62-wallpaper.sh.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    # A copy beside its own images, so the repo's folder is never touched.
    export WP="$BATS_TEST_TMPDIR/wallpapers"
    mkdir -p "$WP"
    cp "$REPO/wallpapers/b-wallpaper" "$WP/"
    touch "$WP/a.png" "$WP/b.png"
    fake_cmd feh 'echo "feh $*" >> "$FAKE_LOG"'
}

teardown() { [[ -z "${LOOP:-}" ]] || kill "$LOOP" 2>/dev/null || true; }

@test "wallpaper: auto shows the next image every SECONDS" {
    "$WP/b-wallpaper" auto 1 3>&- & LOOP=$!
    sleep 2.5
    [ "$(grep -c '^feh ' "$FAKE_LOG")" -ge 2 ]
    grep -q "a.png" "$FAKE_LOG"
    grep -q "b.png" "$FAKE_LOG"
}

@test "wallpaper: a second auto exits at once while one is running" {
    "$WP/b-wallpaper" auto 100 3>&- & LOOP=$!
    sleep 0.5
    run timeout 5 "$WP/b-wallpaper" auto 100
    [ "$status" -eq 0 ]
}

@test "wallpaper: auto with one image leaves it alone" {
    rm "$WP/b.png"
    "$WP/b-wallpaper" auto 1 3>&- & LOOP=$!
    sleep 2.5
    ! grep -q '^feh ' "$FAKE_LOG"
}

@test "wallpaper: auto with a bad interval stops with usage" {
    for bad in 0 -5 abc; do
        run "$WP/b-wallpaper" auto "$bad"
        [ "$status" -eq 2 ]
    done
}

@test "wallpaper: default.jpg is tracked, other images stay gitignored" {
    # The container's git does not own the bind-mounted repo: trust it for this check.
    run git -c safe.directory='*' -C "$REPO" check-ignore -q wallpapers/default.jpg
    [ "$status" -eq 1 ]
    git -c safe.directory='*' -C "$REPO" check-ignore -q wallpapers/mine.png
}

@test "wallpaper: the module writes the 5-minute loop into i3's config" {
    mkdir -p "$HOME/.i3rc"
    # The repo is mounted read-only and the module chmods the script: run a copy.
    local copy="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$copy/basic" "$copy/wallpapers"
    cp -r "$REPO/lib" "$copy/"
    cp "$REPO/basic/62-wallpaper.sh" "$copy/basic/"
    cp "$REPO/wallpapers/b-wallpaper" "$copy/wallpapers/"
    run bash "$copy/basic/62-wallpaper.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'exec_always --no-startup-id ~/.local/bin/b-wallpaper auto 300' \
        "$HOME/.i3rc/09-wallpaper.local"
}
