#!/usr/bin/env bash
# MEGAcmd — MEGA sync from the terminal: mega-login, mega-sync, mega-get… Works
# over ssh, no desktop needed. Official apt repo, one build per Ubuntu release
# (xUbuntu_<version>). Replaces MEGAsync: a machine that still has it loses it.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/mega-cmd.service"
WANTS="$UNIT_DIR/default.target.wants/mega-cmd.service"
# What the package's postinst writes, outside dpkg's records. It points at its
# own keyring, so our mega.nz.list beside it would make apt fail on Signed-By.
# The override exists for the unit tests only.
MEGA_SOURCES="${BLE_MEGA_SOURCES:-/etc/apt/sources.list.d/megaio.sources}"
MEGA_KEYRING=/etc/apt/keyrings/meganz-archive-keyring.gpg
# Left behind by the old megasync module.
OLD_WRAPPER="$HOME/.local/bin/megasync-wait-tray"
OLD_AUTOSTART="$HOME/.config/autostart/megasync.desktop"

is_installed() { apt_installed megacmd; }
# The user's systemd: absent in a container, unreachable from the boot cron.
user_systemd() { has_cmd systemctl && systemctl --user show-environment &>/dev/null; }

[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "MEGAcmd — uninstall"
    if [[ -e "$UNIT" ]] && user_systemd; then
        run systemctl --user disable --now mega-cmd.service &>/dev/null || true
    fi
    remove_files "$WANTS" "$UNIT"
    apt_remove megacmd
    apt_repo_drop mega.nz
    apt_installed megasync || remove_files --sudo "$MEGA_SOURCES" "$MEGA_KEYRING"
    ok "MEGAcmd removed. Your synced folders, your cloud files and ~/.megaCmd (the login) are not touched."
    exit 0
fi

title "MEGAcmd"

# ── 1. the package ───────────────────────────────────────────────────────────
if is_installed; then
    skip "MEGAcmd already installed."
else
    apt_ensure curl gnupg

    # The package already wrote its own source (MEGAsync, or an earlier MEGAcmd).
    if [[ ! -f "$MEGA_SOURCES" ]]; then
        # Release number drives the repo folder (e.g. 26.04 → xUbuntu_26.04).
        release="$(lsb_release -rs 2>/dev/null || echo '')"
        if [[ -z "$release" ]]; then
            fail "Could not determine Ubuntu release — install MEGAcmd manually from https://mega.io/cmd."
            exit 1
        fi
        base="https://mega.nz/linux/repo/xUbuntu_${release}"
        apt_repo_add mega.nz \
            "${base}/Release.key" \
            "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mega.nz.gpg] ${base}/ ./"
    fi

    # apt_ensure refreshes once when a package has no candidate, so an unpublished
    # release reads as "no candidate". Not a bare `apt-get update`: that needs root.
    apt_ensure megacmd

    if ! apt_installed megacmd && [[ "$DRY_RUN" != true ]]; then
        warn "No megacmd package for this Ubuntu release (it may not be published yet)."
        warn "Remove /etc/apt/sources.list.d/mega.nz.list and grab the .deb from https://mega.io/cmd."
        exit 0
    fi
fi
# The postinst has written megaio.sources by now: ours is a duplicate.
[[ -f "$MEGA_SOURCES" ]] && apt_repo_drop mega.nz

# ── 2. MEGAsync goes ─────────────────────────────────────────────────────────
# Its syncs live in its own config, which MEGAcmd can't read: re-add them.
if apt_installed megasync; then
    warn "MEGAsync is installed — removing it. Its syncs are NOT carried over."
    apt_remove megasync
    warn "Re-add each sync with: mega-sync <local folder> <MEGA folder>"
fi
remove_files "$OLD_WRAPPER" "$OLD_AUTOSTART"

# ── 3. the server, started at boot ───────────────────────────────────────────
# mega-* commands talk to mega-cmd-server and spawn it when it isn't running, so
# without this a sync only runs after the first command since boot.
write_gen "$UNIT" <<'UNIT'
[Unit]
Description=MEGAcmd server — keeps the mega-sync folders in sync
After=network-online.target

[Service]
ExecStart=/usr/bin/mega-cmd-server --do-not-log-to-stdout
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
UNIT
# The symlink `systemctl --user enable` makes, by hand: it needs no running
# user manager, so the boot cron enables it too.
if [[ "$(readlink "$WANTS" 2>/dev/null)" != "$UNIT" ]]; then
    run mkdir -p "$(dirname "$WANTS")"
    run ln -sfn "$UNIT" "$WANTS"
    ok "mega-cmd.service enabled."
fi
if user_systemd; then
    run systemctl --user daemon-reload
    if ! systemctl --user is-active --quiet mega-cmd.service; then
        # A mega-* command may already have spawned a server: one only.
        run pkill -x mega-cmd-server || true
        if run systemctl --user start mega-cmd.service; then
            ok "mega-cmd.service started."
        else
            warn "mega-cmd.service did not start — see: journalctl --user -u mega-cmd"
        fi
    fi
else
    skip "No user systemd here — mega-cmd.service starts at the next login."
fi

# Linger: the user's services run from boot, not from the first login. That is
# what keeps a server's syncs going with nobody logged in.
me="$(id -un)"
if has_cmd loginctl && [[ "$(loginctl show-user "$me" -p Linger --value 2>/dev/null)" != yes ]]; then
    if can_sudo; then
        run sudo loginctl enable-linger "$me" && ok "Linger on: MEGAcmd syncs from boot."
    else
        warn "sudo unavailable — linger left off: syncs start at login, not at boot."
    fi
fi

# The saved login, read from disk: any mega-* command would spawn a server.
[[ -s "$HOME/.megaCmd/session" ]] \
    || warn "Not logged in. Run mega-cmd, then: login <email>  (mega-login asks for no password: it wants it on the command line)"
ok "MEGAcmd ready."
