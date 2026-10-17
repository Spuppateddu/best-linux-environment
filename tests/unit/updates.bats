#!/usr/bin/env bats
# updates/: b-update, basic/26-update.sh that links it, and advanced/auto-updates.sh.

load helpers

# bats runs one setup(): keep the shared one under another name and call it.
eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    export BLE_APT_CONF_D="$BATS_TEST_TMPDIR/apt.conf.d"
    export BLE_REBOOT_REQUIRED="$BATS_TEST_TMPDIR/reboot-required"
    mkdir -p "$BLE_APT_CONF_D"
    fake_cmd apt 'echo "apt $*" >> "$FAKE_LOG"'
    # Only what b-update and the fakes need, so a real snap or flatpak on the
    # test machine never decides which steps run.
    export TOOLS="$BATS_TEST_TMPDIR/tools"
    mkdir -p "$TOOLS"
    local t; for t in bash cat grep mkdir mv; do ln -s "$(command -v "$t")" "$TOOLS/$t"; done
}

b_update() {
    run env PATH="$FAKE_BIN:$TOOLS" bash "$REPO/updates/b-update" "$@"
}

@test "b-update: apt update, full-upgrade, autoremove, in that order" {
    b_update
    [ "$status" -eq 0 ]
    diff <(cat "$FAKE_LOG") - <<'LOG'
sudo apt update
apt update
sudo apt full-upgrade
apt full-upgrade
sudo apt autoremove --purge
apt autoremove --purge
LOG
}

@test "b-update -y: apt and flatpak do not ask; snap and flatpak run when present" {
    fake_cmd snap 'echo "snap $*" >> "$FAKE_LOG"'
    fake_cmd flatpak 'echo "flatpak $*" >> "$FAKE_LOG"'
    b_update -y
    [ "$status" -eq 0 ]
    grep -qx 'apt full-upgrade -y' "$FAKE_LOG"
    grep -qx 'apt autoremove --purge -y' "$FAKE_LOG"
    grep -qx 'snap refresh' "$FAKE_LOG"
    grep -qx 'flatpak update -y' "$FAKE_LOG"
}

@test "b-update: stops at the first step that fails" {
    fake_cmd apt 'echo "apt $*" >> "$FAKE_LOG"; [[ "$1" != update ]]'
    b_update
    [ "$status" -ne 0 ]
    ! grep -q 'full-upgrade' "$FAKE_LOG"
}

@test "b-update: says when a reboot is needed, and only then" {
    b_update
    [[ "$output" != *"reboot is needed"* ]]
    touch "$BLE_REBOOT_REQUIRED"
    b_update
    [[ "$output" == *"reboot is needed"* ]]
}

@test "b-update: an unknown option is refused before anything runs" {
    b_update --nope
    [ "$status" -eq 2 ]
    [ ! -s "$FAKE_LOG" ]
}

@test "26-update: links b-update into ~/.local/bin, and a re-run changes nothing" {
    run bash "$REPO/basic/26-update.sh" </dev/null
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.local/bin/b-update")" = "$REPO/updates/b-update" ]
    run bash "$REPO/basic/26-update.sh" </dev/null
    [[ "$output" == *"already linked"* ]]
}

@test "auto-updates: apt reads the file and adds the -updates pocket" {
    command -v apt-config >/dev/null || skip "no apt-config here"
    run apt-config -c "$REPO/updates/52best-linux-environment" dump
    [ "$status" -eq 0 ]
    [[ "$output" == *'Unattended-Upgrade::Allowed-Origins:: "${distro_id}:${distro_codename}-updates";'* ]]
    [[ "$output" == *'APT::Periodic::Unattended-Upgrade "1";'* ]]
}

@test "auto-updates: installs unattended-upgrades when missing, then the file" {
    # -o root -g root needs real root: copy the file as this user instead.
    fake_cmd sudo '[[ "$1" == -n ]] && shift; echo "sudo $*" >> "$FAKE_LOG"
        if [[ "$1" == install ]]; then install -D -m 0644 "${@: -2}"; else "$@"; fi'
    run bash "$REPO/advanced/auto-updates.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'apt-get install -y unattended-upgrades' "$FAKE_LOG"
    cmp "$REPO/updates/52best-linux-environment" "$BLE_APT_CONF_D/52best-linux-environment"
}

@test "auto-updates --check: yes only with both the file and the package" {
    run bash "$REPO/advanced/auto-updates.sh" --check
    [ "$status" -eq 1 ]
    touch "$BLE_APT_CONF_D/52best-linux-environment"
    run bash "$REPO/advanced/auto-updates.sh" --check
    [ "$status" -eq 1 ]
    pkg_status unattended-upgrades installed
    run bash "$REPO/advanced/auto-updates.sh" --check
    [ "$status" -eq 0 ]
}

@test "auto-updates --uninstall: removes the file, keeps unattended-upgrades" {
    pkg_status unattended-upgrades installed
    touch "$BLE_APT_CONF_D/52best-linux-environment"
    run bash "$REPO/advanced/auto-updates.sh" --uninstall </dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$BLE_APT_CONF_D/52best-linux-environment" ]
    ! grep -q 'apt-get remove' "$FAKE_LOG"
}

@test "auto-updates: no sudo (the boot cron) touches nothing" {
    fake_cmd sudo '[[ "$1" == -n ]] && exit 1; echo "sudo $*" >> "$FAKE_LOG"'
    run bash -c "bash '$REPO/advanced/auto-updates.sh' < /dev/null"
    [ "$status" -eq 0 ]
    [ ! -s "$FAKE_LOG" ]
    [ ! -e "$BLE_APT_CONF_D/52best-linux-environment" ]
}

# count_env  — fake apt lists and dpkg status, and an apt-get that says it
# would install $INST packages, logging each simulation it runs.
count_env() {
    export BLE_APT_LISTS="$BATS_TEST_TMPDIR/lists" BLE_DPKG_STATUS="$BATS_TEST_TMPDIR/status"
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
    mkdir -p "$BLE_APT_LISTS"; touch "$BLE_DPKG_STATUS"
    export INST="${1:-3}"
    fake_cmd apt-get 'echo "apt-get $*" >> "$FAKE_LOG"
        for ((i = 0; i < INST; i++)); do echo "Inst pkg$i [1] (2 Ubuntu)"; echo "Conf pkg$i"; done'
}

@test "b-update --count: the packages full-upgrade would install, without root" {
    count_env 3
    b_update --count
    [ "$status" -eq 0 ]
    [ "$output" = 3 ]
    grep -qx 'apt-get -s -o Debug::NoLocking=1 full-upgrade' "$FAKE_LOG"
    ! grep -q sudo "$FAKE_LOG"
}

@test "b-update --count: nothing waiting is 0, not an error" {
    count_env 0
    b_update --count
    [ "$status" -eq 0 ]
    [ "$output" = 0 ]
}

@test "b-update --count: cached until apt update or an upgrade changes things" {
    count_env 3
    b_update --count
    INST=5 b_update --count
    [ "$output" = 3 ]
    [ "$(grep -c 'apt-get' "$FAKE_LOG")" -eq 1 ]
    # An upgrade rewrites dpkg's status; apt update rewrites the lists.
    touch -d '+1 minute' "$BLE_DPKG_STATUS"
    INST=5 b_update --count
    [ "$output" = 5 ]
    touch -d '+2 minutes' "$BLE_APT_LISTS"
    INST=1 b_update --count
    [ "$output" = 1 ]
}
