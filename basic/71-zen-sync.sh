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

# ── Refuse to write under a running Zen ──────────────────────────────────────
# The lock symlink and .parentlock exist only while Zen is open; pgrep is the
# belt-and-braces check. DRY_RUN just previews, so let it through.
if [[ "$DRY_RUN" != true ]] \
   && { [[ -e "$PROFILE/lock" || -e "$PROFILE/.parentlock" ]] && pgrep -x zen >/dev/null 2>&1; }; then
    warn "Zen is running — close it and re-run, or it will overwrite these files on exit."
    warn "Skipping config this pass."
    exit 0
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

for f in \
    user.js \
    zen-keyboard-shortcuts.json \
    zen-themes.json \
    containers.json \
    xulstore.json \
    handlers.json \
    search.json.mozlz4
do
    copy_file "$f"
done

# ── chrome/ (Zen mods + userChrome CSS) — mirror the whole tree ──────────────
if [[ -d "$SRC/chrome" ]]; then
    if [[ -d "$PROFILE/chrome" ]] && diff -rq "$SRC/chrome" "$PROFILE/chrome" >/dev/null 2>&1; then
        skip "chrome/ already up to date."
    else
        [[ -e "$PROFILE/chrome" ]] && run cp -a "$PROFILE/chrome" "$PROFILE/chrome.backup.$$"
        run mkdir -p "$PROFILE/chrome"
        run cp -a "$SRC/chrome/." "$PROFILE/chrome/"
        ok "applied chrome/ (mods + CSS)"
    fi
fi

ok "Zen config applied — restart Zen to see it."
