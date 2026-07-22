#!/usr/bin/env bash
# Zen browser — apply my portable config into the installed profile.
#
# Runs after 70-zen-browser.sh (which installs the binary). It copies the public,
# non-personal config payload in basic/zen-config/ (shortcuts, toolbar/sidebar
# layout, Zen mods + their CSS, containers, file handlers, curated prefs via
# user.js) into the active Zen profile. It deliberately carries NO personal data:
# no bookmarks/history (places.sqlite), cookies, logins/keys, saved sessions/tabs,
# form history, or per-site permissions.
#
# Two things make this safe to re-run (it's on the boot-update path):
#   1. Zen must be closed. Zen rewrites prefs.js on exit and can clobber the JSON
#      state files, so overwriting them under a live browser would be lost. If Zen
#      is running we skip with a warning rather than corrupt the profile.
#   2. Every file we replace is backed up (*.backup.$$) before it's overwritten.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Zen config"
require_desktop "Zen config"

SRC="$BLE_ROOT/basic/zen-config"
ZEN_ROOT="$HOME/.config/zen"

if [[ ! -d "$SRC" ]]; then
    warn "No config payload at $SRC — nothing to apply."
    exit 0
fi

# Only meaningful once Zen exists. On a server 70 skipped install; here too.
if ! { [[ -x "$HOME/.local/bin/zen" ]] || has_cmd zen; }; then
    skip "Zen not installed — skipping config (install it first: ./install.sh basic)."
    exit 0
fi

# ── Resolve the active profile from profiles.ini ─────────────────────────────
# Zen (like Firefox) picks the profile locked to the running install, recorded as
# `Default=<path>` under an [InstallXXXX] section. Fall back to the [General]-level
# default (Default=1 on a [ProfileN]) and finally to the lone profile on disk.
# The path is relative when IsRelative=1 (always, in practice) → prefix with root.
resolve_profile() {
    local ini="$ZEN_ROOT/profiles.ini" rel=""
    [[ -f "$ini" ]] || return 1

    # 1. Install-locked default (what Zen actually launches).
    rel="$(awk -F= '
        /^\[Install/      {ins=1; next}
        /^\[/             {ins=0}
        ins && $1=="Default" {print $2; exit}
    ' "$ini")"

    # 2. Profile flagged Default=1.
    if [[ -z "$rel" ]]; then
        rel="$(awk -F= '
            /^\[Profile/ {p=1; path=""; def=0; next}
            /^\[/        {p=0}
            p && $1=="Path"    {path=$2}
            p && $1=="Default" && $2=="1" {def=1}
            p && def && path   {print path; exit}
        ' "$ini")"
    fi

    [[ -n "$rel" && -d "$ZEN_ROOT/$rel" ]] && { printf '%s\n' "$ZEN_ROOT/$rel"; return 0; }
    return 1
}

PROFILE=""
if [[ -d "$ZEN_ROOT" ]]; then
    PROFILE="$(resolve_profile || true)"
fi

if [[ -z "$PROFILE" ]]; then
    warn "No Zen profile yet — launch Zen once so it creates one, then re-run:"
    warn "  ./install.sh basic   (or ./install.sh update)"
    exit 0
fi
step "Target profile: ${PROFILE/#$HOME/\~}"

# ── Detect a running Zen (but don't bail on it) ──────────────────────────────
# The two file groups have different safety profiles under a live Zen:
#   • Safe: user.js and chrome/ (userChrome.css + mods). Zen only ever READS these
#     — it never writes them back — and applies them at the next startup. Copying
#     them while Zen runs can't be clobbered; they just need a restart to show.
#     The Gruvbox theme lives here, so it ALWAYS syncs on every installer run.
#   • Volatile: the JSON state files (layout/shortcuts/containers/…). Zen rewrites
#     these on exit, so writing under a live browser would be lost — defer them
#     until Zen is closed.
# The lock symlink and .parentlock exist only while Zen is open; pgrep is the
# belt-and-braces check. DRY_RUN just previews, so treat it as "not running".
ZEN_RUNNING=false
if [[ "$DRY_RUN" != true ]] \
   && { [[ -e "$PROFILE/lock" || -e "$PROFILE/.parentlock" ]] && pgrep -x zen >/dev/null 2>&1; }; then
    ZEN_RUNNING=true
fi

# ── Copy one file, backing up any existing real file first ───────────────────
copy_file() {
    local rel="$1" src="$SRC/$1" dst="$PROFILE/$1"
    [[ -f "$src" ]] || return 0
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        skip "$rel already up to date."
        return
    fi
    run mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" ]]; then
        run cp -a "$dst" "$dst.backup.$$"
    fi
    run cp -a "$src" "$dst"
    ok "applied $rel"
}

# ── Always-safe: prefs (user.js) + chrome/ (theme + mods) ────────────────────
# Never written by Zen, so these sync on every run regardless of whether Zen is
# open. This is what carries the Gruvbox theme; it takes effect on next restart.
copy_file user.js

if [[ -d "$SRC/chrome" ]]; then
    if [[ -d "$PROFILE/chrome" ]] && diff -rq "$SRC/chrome" "$PROFILE/chrome" >/dev/null 2>&1; then
        skip "chrome/ already up to date."
    else
        [[ -e "$PROFILE/chrome" ]] && run cp -a "$PROFILE/chrome" "$PROFILE/chrome.backup.$$"
        run mkdir -p "$PROFILE/chrome"
        run cp -a "$SRC/chrome/." "$PROFILE/chrome/"
        ok "applied chrome/ (theme + mods)"
    fi
fi

# ── Volatile state files — only safe to write while Zen is closed ────────────
# Zen rewrites these on exit; writing under a live browser would be clobbered.
if [[ "$ZEN_RUNNING" == true ]]; then
    warn "Zen is running — deferred the volatile state files (layout/shortcuts/containers)."
    warn "Close Zen and re-run to sync those too. The theme (user.js + chrome/) was applied."
else
    for f in \
        zen-keyboard-shortcuts.json \
        zen-themes.json \
        containers.json \
        xulstore.json \
        handlers.json \
        search.json.mozlz4
    do
        copy_file "$f"
    done
fi

ok "Zen config applied — restart Zen to see it."
