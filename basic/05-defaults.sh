#!/usr/bin/env bash
# The baseline config nothing else owns: fonts.local, ~/.local/bin on PATH,
# ~/.ssh/config, git's defaults, ~/.Xresources. Created when missing, never after.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Baseline configuration — creating whatever is missing"

# Every write below is --if-missing or ensure_line, so a file you have edited is
# left exactly as it is — even by ./setup.sh's reset. See lib/common.sh.
skip "Only files that aren't there are written; nothing here is ever overwritten."

# ── 1. fonts.local ───────────────────────────────────────────────────────────
# The per-machine sizes file. All-commented, so it changes nothing until you
# uncomment a line — but a new PC now has the file to edit instead of a hint.
FONTS_LOCAL="${BLE_FONTS_LOCAL:-$BLE_ROOT/fonts.local}"
FONTS_EXAMPLE="$BLE_ROOT/fonts.local.example"
if is_server; then
    skip "Server profile — no fonts.local (nothing here renders text)."
elif [[ ! -f "$FONTS_EXAMPLE" ]]; then
    warn "$FONTS_EXAMPLE missing — cannot seed fonts.local."
else
    config_write "$FONTS_LOCAL" --if-missing < "$FONTS_EXAMPLE"
    [[ "$CONFIG_WRITTEN" == true ]] && ok "Edit ${FONTS_LOCAL/#$HOME/\~}, then re-run — every boot re-applies it."
fi

# ── 2. ~/.local/bin on PATH ──────────────────────────────────────────────────
# lazygit, yazi, fzf and temps all land here. Ubuntu's own ~/.profile adds it
# only if the directory already exists, so create it before anything reads that.
run mkdir -p "$HOME/.local/bin"

config_write "$HOME/.profile" --if-missing <<'EOF'
# ~/.profile — read by login shells. Seeded by best-linux-environment because
# this machine had none; it is yours to edit from here on.

# if running bash, read ~/.bashrc too
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH" ; fi
EOF

# The insert half: an existing ~/.profile that never learned about ~/.local/bin
# would leave every binary above off PATH.
if [[ "$CONFIG_WRITTEN" == true ]]; then
    skip "~/.profile was just written with the PATH line in it."
else
    ensure_line "$HOME/.profile" '\.local/bin' \
        'if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH" ; fi'
    [[ "$LINE_ADDED" == true ]] && warn "Log out and back in (or source ~/.profile) to pick up ~/.local/bin."
fi

# ── 3. ~/.ssh/config ─────────────────────────────────────────────────────────
# The key itself is basic/20-ssh.sh's; this is only the client defaults, so a
# long-running remote session doesn't drop silently.
run mkdir -p "$HOME/.ssh"
run chmod 700 "$HOME/.ssh"
config_write "$HOME/.ssh/config" --if-missing <<'EOF'
# Seeded by best-linux-environment — yours from here on. Per-host blocks go
# above this one: for `Host *` settings, the first value wins.
Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
# ssh refuses to read a config other users can write.
[[ "$CONFIG_WRITTEN" == true && "$DRY_RUN" != true ]] && chmod 600 "$HOME/.ssh/config"

# ── 4. git ───────────────────────────────────────────────────────────────────
# Per key, not per file: a ~/.gitconfig holding only your name still gets these,
# and a key you have set yourself is never touched.
if ! has_cmd git; then
    skip "git not installed yet — its defaults are set on the next run."
else
    git_default() {
        local key="$1" value="$2"
        if git config --global --get "$key" >/dev/null 2>&1; then
            skip "git $key already set — left as it is."
        elif [[ "$DRY_RUN" == true ]]; then
            printf '%s  would set:%s git config --global %s %s\n' "$C_DIM" "$C_OFF" "$key" "$value"
        else
            git config --global "$key" "$value"
            ok "git $key = $value"
        fi
    }
    git_default init.defaultBranch main
    git_default pull.rebase false
    git_default push.default simple
    has_cmd vim && git_default core.editor vim

    # The two nobody can guess for you. Wrong values here end up inside commits,
    # so this says the commands rather than inventing an identity.
    for key in user.name user.email; do
        git config --global --get "$key" >/dev/null 2>&1 && continue
        warn "git $key is unset — commits will be refused until you set it:"
        warn "    git config --global $key \"…\""
    done
fi

# ── 5. ~/.Xresources ─────────────────────────────────────────────────────────
# X apps read their font rendering from here, and ./boot.sh merges the file at
# every boot — but only if there is one.
if is_desktop; then
    config_write "$HOME/.Xresources" --if-missing <<'EOF'
! Seeded by best-linux-environment — yours from here on.
! Font rendering for X apps that take it from here (xterm, dmenu, Xft clients).
Xft.antialias: 1
Xft.hinting:   1
Xft.hintstyle: hintslight
Xft.rgba:      rgb
Xft.lcdfilter: lcddefault
EOF
    if [[ "$CONFIG_WRITTEN" == true && -n "${DISPLAY:-}" ]] && has_cmd xrdb; then
        run xrdb -merge "$HOME/.Xresources" 2>/dev/null && ok "X resources merged." \
            || skip "Could not merge ~/.Xresources — it applies at the next login."
    fi
else
    skip "Server profile — no ~/.Xresources (no X to read it)."
fi

ok "Baseline configuration ready."
