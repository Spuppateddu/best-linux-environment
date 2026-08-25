#!/usr/bin/env bash
# A root systemd timer that powers this machine off once nobody is using it.
# Here, not in a shell repo: it is a systemd unit, so the shell is irrelevant.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/idle-poweroff"

title "Idle poweroff"

if [[ ! -d "$SRC" ]]; then
    skip "No idle-poweroff/ in this repo — nothing to install."
    exit 0
fi
# The documented "booted with systemd" test; false inside a container even when
# the systemctl binary is present.
if ! has_cmd systemctl || [[ ! -d /run/systemd/system ]]; then
    skip "Not booted with systemd — idle poweroff needs its timer, skipping."
    exit 0
fi

# ── b-idle, first: it works even if the root half below cannot be installed ──
# A script in ~/.local/bin rather than a function in each shell's alias file:
# one copy, and zsh and bash both find it on PATH (see basic/05-defaults.sh).
run mkdir -p "$HOME/.local/bin"
if cmp -s "$SRC/b-idle" "$HOME/.local/bin/b-idle"; then
    skip "b-idle already current."
else
    run install -m 0755 "$SRC/b-idle" "$HOME/.local/bin/b-idle"
    ok "b-idle installed to ~/.local/bin."
fi

# can_sudo() passes whenever a terminal exists, so failing it means cron.
# Quietly: warnings in every boot log are noise nobody reads.
if ! can_sudo; then
    skip "No terminal to authenticate sudo — the root half is left as it is."
    skip "Run ./setup.sh from a terminal to install or refresh the timer."
    exit 0
fi

# Without it a desktop falls back to "cannot measure, assume in use" and never
# powers off; a headless machine never needs it but loses nothing by having it.
apt_ensure xprintidle

# Two things that can power the machine off is one too many, and autosuspend
# does not count a connected ssh session as activity. Ours knows about ssh.
if systemctl cat autosuspend.service &>/dev/null \
    && systemctl is-enabled --quiet autosuspend.service 2>/dev/null; then
    warn "autosuspend.service is enabled too, and it can power this machine off"
    warn "behind idle-poweroff's back — open ssh session or not."
    run sudo systemctl disable --now autosuspend.service &>/dev/null || true
    run sudo systemctl disable --now autosuspend-detect-suspend.service &>/dev/null || true
    run sudo systemctl mask autosuspend.service &>/dev/null || true
    ok "autosuspend masked; /etc/autosuspend.conf left untouched on disk."
    ok "Undo with: sudo systemctl unmask --now autosuspend.service"
fi

# ── the root half ────────────────────────────────────────────────────────────
# Copies only when the contents differ, so ./boot.sh re-running this at every
# boot is silent. CHANGED decides whether the timer needs restarting.
CHANGED=false
install_root_file() {
    local mode="$1" src="$2" dest="$3"
    if [[ ! -r "$src" ]]; then
        warn "Missing $src — skipping ${dest}."
        return 1
    fi
    if cmp -s "$src" "$dest"; then
        skip "$dest already current."
        return 0
    fi
    step "installing $dest"
    if run sudo install -D -m "$mode" -o root -g root "$src" "$dest"; then
        CHANGED=true
        return 0
    fi
    warn "Could not write $dest."
    return 1
}

install_root_file 0755 "$SRC/idle-poweroff.sh"      /usr/local/sbin/idle-poweroff || true
install_root_file 0644 "$SRC/idle-poweroff.service" /etc/systemd/system/idle-poweroff.service || true
install_root_file 0644 "$SRC/idle-poweroff.timer"   /etc/systemd/system/idle-poweroff.timer || true

# Machine-local, like settings.local: written once so ./boot.sh can never undo
# the numbers you chose for this particular machine.
if [[ -e /etc/idle-poweroff.conf ]]; then
    skip "/etc/idle-poweroff.conf exists — your settings kept."
else
    install_root_file 0644 "$SRC/idle-poweroff.conf" /etc/idle-poweroff.conf || true
fi

if [[ "$DRY_RUN" == true ]]; then
    skip "dry run — timer not reloaded or enabled."
    exit 0
fi

if [[ "$CHANGED" == true ]]; then
    sudo systemctl daemon-reload || warn "systemctl daemon-reload failed."
    sudo systemctl enable --quiet idle-poweroff.timer 2>/dev/null \
        || warn "Could not enable idle-poweroff.timer."
    # restart, not start: a running timer still holds the OLD unit file.
    if sudo systemctl restart idle-poweroff.timer; then
        ok "idle-poweroff.timer installed and running."
    else
        warn "Could not start it — see: systemctl status idle-poweroff.timer"
        exit 0
    fi
elif systemctl is-active --quiet idle-poweroff.timer; then
    skip "idle-poweroff.timer already running."
else
    sudo systemctl enable --now idle-poweroff.timer \
        && ok "idle-poweroff.timer enabled." \
        || warn "Could not enable idle-poweroff.timer."
fi

# Said out loud: a machine that powers itself off should never be a surprise.
mins=$(awk -F= '/^[[:space:]]*IDLE_MINUTES=/     { v = $2 } END { print (v ? v : 60) }' /etc/idle-poweroff.conf 2>/dev/null)
locked=$(awk -F= '/^[[:space:]]*LOCKED_MINUTES=/ { v = $2 } END { print (v ? v : 10) }' /etc/idle-poweroff.conf 2>/dev/null)
ok "This machine now powers itself off after ${mins:-60} min unused (${locked:-10} min with the screen locked)."
ok "Never while ssh is connected, media is playing, or an agent or tmux job is printing."
ok "Check it with 'b-idle'; pause it with 'b-idle off'; settings in /etc/idle-poweroff.conf."
