#!/usr/bin/env bats
# lib/common.sh — the apt, file and profile helpers every module stands on.

load helpers

@test "apt_installed: yes for an installed package" {
    pkg_status brave-browser installed
    ble 'apt_installed brave-browser'
    [ "$status" -eq 0 ]
}

@test "apt_installed: no for a removed package whose config is left (rc)" {
    # The Brave bug: dpkg -s says yes here, so a removed app never left the list.
    pkg_status brave-browser config-files
    ble 'apt_installed brave-browser'
    [ "$status" -eq 1 ]
}

@test "apt_installed: no for a package dpkg has never seen" {
    ble 'apt_installed nothing-here'
    [ "$status" -eq 1 ]
}

@test "apt_remove: removes only the packages really installed" {
    pkg_status brave-browser installed
    pkg_status brave-keyring config-files
    ble 'apt_remove brave-browser brave-keyring'
    [ "$status" -eq 0 ]
    grep -qx 'apt-get remove -y brave-browser' "$FAKE_LOG"
}

@test "apt_remove: nothing installed means no apt call at all" {
    pkg_status brave-browser config-files
    ble 'apt_remove brave-browser'
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to remove"* ]]
    ! grep -q apt-get "$FAKE_LOG"
}

@test "apt_remove: --dry-run removes nothing" {
    pkg_status okular installed
    DRY_RUN=true ble 'apt_remove okular'
    [ "$status" -eq 0 ]
    [[ "$output" == *"would remove"*okular* ]]
    ! grep -q apt-get "$FAKE_LOG"
}

@test "apt_ensure: a removed (rc) package is installed again" {
    pkg_status brave-browser config-files
    ble 'apt_ensure brave-browser'
    [ "$status" -eq 0 ]
    grep -qx 'apt-get install -y brave-browser' "$FAKE_LOG"
}

@test "apt_ensure: an installed package is left alone" {
    pkg_status git installed
    ble 'apt_ensure git'
    [ "$status" -eq 0 ]
    ! grep -q 'apt-get install' "$FAKE_LOG"
}

@test "remove_files: deletes what exists, skips what does not" {
    mkdir -p "$HOME/a"; touch "$HOME/a/one"
    ble 'remove_files "$HOME/a/one" "$HOME/a/missing"'
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/a/one" ]
}

@test "remove_files: --dry-run deletes nothing" {
    touch "$HOME/keep"
    DRY_RUN=true ble 'remove_files "$HOME/keep"'
    [ "$status" -eq 0 ]
    [ -e "$HOME/keep" ]
}

@test "ensure_line: appends once, then leaves the file alone" {
    ble 'ensure_line "$HOME/rc" "^export FOO=" "export FOO=1"; ensure_line "$HOME/rc" "^export FOO=" "export FOO=1"'
    [ "$status" -eq 0 ]
    [ "$(grep -c FOO "$HOME/rc")" -eq 1 ]
}

@test "ensure_line: never glues onto a last line with no newline" {
    printf 'first' > "$HOME/rc"
    ble 'ensure_line "$HOME/rc" "^second" "second"'
    [ "$(sed -n 2p "$HOME/rc")" = second ]
}

@test "link: makes the symlink, and a second run changes nothing" {
    mkdir -p "$HOME/src"
    ble 'link "$HOME/src" "$HOME/dst"; link "$HOME/src" "$HOME/dst"'
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/dst")" = "$HOME/src" ]
    [[ "$output" == *"already linked"* ]]
}

@test "link: a real file in the way is backed up, never lost" {
    mkdir -p "$HOME/src"; echo mine > "$HOME/dst"
    ble 'link "$HOME/src" "$HOME/dst"'
    [ -L "$HOME/dst" ]
    grep -qx mine "$HOME"/dst.backup.*
}

@test "is_desktop: BLE_PROFILE forces the profile" {
    BLE_PROFILE=server ble 'is_server'
    [ "$status" -eq 0 ]
    BLE_PROFILE=desktop ble 'is_desktop'
    [ "$status" -eq 0 ]
}

@test "is_minimal: a server, labelled minimal" {
    BLE_PROFILE=minimal ble 'is_server && is_minimal && profile_label'
    [ "$status" -eq 0 ]
    [ "$output" = minimal ]
}

@test "profile_init: the env wins, else the remembered profile, else auto" {
    ble 'profile_init; echo "$BLE_PROFILE"'
    [ "$output" = auto ]
    mkdir -p "$BLE_STATE_DIR"; echo minimal > "$BLE_STATE_DIR/profile"
    ble 'profile_init; echo "$BLE_PROFILE"'
    [ "$output" = minimal ]
    BLE_PROFILE=server ble 'profile_init; echo "$BLE_PROFILE"'
    [ "$output" = server ]
}

@test "remember_shell: rejects anything but zsh or bash" {
    ble 'remember_shell fish'
    [ "$status" -eq 1 ]
    ble 'remember_shell bash'
    [ "$(cat "$BLE_STATE_DIR/shell")" = bash ]
}

# A real upstream and clone in the test's dir; `commit_up FILE TEXT` adds a commit.
git_pair() {
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    UP="$BATS_TEST_TMPDIR/up" CL="$BATS_TEST_TMPDIR/cl"
    git init -q -b main "$UP"
    printf 'a\nb\nc\nd\n' > "$UP/f"
    git -C "$UP" add f && git -C "$UP" commit -qm one
    git clone -q "$UP" "$CL"
}
commit_up() { printf '%s\n' "$2" > "$UP/$1"; git -C "$UP" add "$1"; git -C "$UP" commit -qm up; }

@test "clone_or_pull: pulls with uncommitted edits and keeps them" {
    git_pair
    printf 'a\nb\nc\nD\n' > "$UP/f"; git -C "$UP" commit -qam up
    printf 'A\nb\nc\nd\n' > "$CL/f"
    ble "clone_or_pull '$UP' '$CL'"
    [ "$status" -eq 0 ]
    [ "$(git -C "$CL" rev-parse HEAD)" = "$(git -C "$UP" rev-parse HEAD)" ]
    [ "$(cat "$CL/f")" = "$(printf 'A\nb\nc\nD')" ]
    [ -z "$(git -C "$CL" stash list)" ]
}

@test "clone_or_pull: edits that clash with upstream stay, and nothing is pulled" {
    git_pair
    local old; old="$(git -C "$CL" rev-parse HEAD)"
    commit_up f upstream
    printf 'mine\n' > "$CL/f"
    ble "clone_or_pull '$UP' '$CL'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"did NOT pull"* ]]
    [ "$(git -C "$CL" rev-parse HEAD)" = "$old" ]
    [ "$(cat "$CL/f")" = mine ]
    [ -z "$(git -C "$CL" stash list)" ]
}

@test "clone_or_pull: a renamed repo gets the new origin and pulls" {
    git_pair
    commit_up f upstream
    git -C "$CL" remote set-url origin https://github.com/me/old-name.git
    ble "clone_or_pull '$UP' '$CL'"
    [ "$status" -eq 0 ]
    [ "$(git -C "$CL" remote get-url origin)" = "$UP" ]
    [ "$(git -C "$CL" rev-parse HEAD)" = "$(git -C "$UP" rev-parse HEAD)" ]
}

@test "repo_id: the ssh and https URLs of one repo match" {
    ble 'repo_id git@github.com:Me/Repo.git; repo_id https://github.com/me/repo/'
    [ "${lines[0]}" = me/repo ]
    [ "${lines[1]}" = me/repo ]
}

@test "clone_or_pull: a checkout with no history in common is kept aside and cloned anew" {
    git_pair
    local old="$BATS_TEST_TMPDIR/old"
    git init -q -b main "$old"
    printf 'mine\n' > "$old/f"
    git -C "$old" add f && git -C "$old" commit -qm mine
    git -C "$old" remote add origin "$UP"
    git -C "$old" fetch -q origin && git -C "$old" branch -q -u origin/main
    ble "clone_or_pull '$UP' '$old'"
    [ "$status" -eq 0 ]
    [ "$(git -C "$old" rev-parse HEAD)" = "$(git -C "$UP" rev-parse HEAD)" ]
    grep -qx mine "$old".backup.*/f
}
