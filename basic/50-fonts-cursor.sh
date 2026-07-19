#!/usr/bin/env bash
# Cross-cutting desktop bits that aren't tied to any single tool: the Nerd Font
# used across the bar/terminal/editor, and the macOS cursor theme.
# These live here (not in i3rc) so the per-tool repos stay light and these run
# even without i3. i3rc's own copies are idempotent, so overlap is harmless.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Fonts & cursor"
require_desktop "Fonts & cursor"

apt_ensure fontconfig x11-xserver-utils

# ── 1. Cascadia Code Nerd Font ───────────────────────────────────────────────
# Check the installed files directly. NOT `fc-list | grep -q`: under `set -o
# pipefail`, grep -q closes the pipe on first match, fc-list dies with SIGPIPE
# (141), the pipeline "fails", and the font re-downloads on every run.
FONT_DIR="$HOME/.local/share/fonts"
if compgen -G "$FONT_DIR/CaskaydiaCove*Nerd*" >/dev/null 2>&1 \
   || fc-list 2>/dev/null | grep -iE "caskaydiacove.*nerd" >/dev/null; then
    skip "CaskaydiaCove Nerd Font already installed."
else
    url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"
    tmp="/tmp/CascadiaCode.$$.zip"
    step "Installing Cascadia Code Nerd Font"
    run mkdir -p "$FONT_DIR"
    run curl -fL --progress-bar -o "$tmp" "$url"
    run unzip -oq "$tmp" -d "$FONT_DIR"
    run rm -f "$tmp"
    run fc-cache -f
    ok "CaskaydiaCove Nerd Font installed."
fi

# ── 2. macOS cursor ──────────────────────────────────────────────────────────
# Must live under ~/.icons: libXcursor's default search path excludes
# ~/.local/share/icons, so xsetroot/i3 couldn't find it there.
CURSOR_THEME="macOS"
CURSOR_VERSION="v2.0.1"
CURSOR_DIR="$HOME/.icons/$CURSOR_THEME"

if [[ -d "$CURSOR_DIR" ]]; then
    skip "$CURSOR_THEME cursor already installed."
else
    url="https://github.com/ful1e5/apple_cursor/releases/download/$CURSOR_VERSION/macOS.tar.xz"
    tmp="/tmp/macOS-cursor.$$.tar.xz"
    step "Installing $CURSOR_THEME cursor ($CURSOR_VERSION)"
    run mkdir -p "$HOME/.icons"
    run curl -fL --progress-bar -o "$tmp" "$url"
    run tar -xf "$tmp" -C "$HOME/.icons"
    run rm -f "$tmp"
    ok "$CURSOR_THEME cursor installed."
fi

# Make it the X11 default (no DE settings GUI under i3).
DEFAULT_INDEX="$HOME/.icons/default/index.theme"
if [[ -f "$DEFAULT_INDEX" ]] && grep -q "Inherits=$CURSOR_THEME" "$DEFAULT_INDEX"; then
    skip "Default cursor already set to $CURSOR_THEME."
else
    run mkdir -p "$HOME/.icons/default"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s Inherits=%s → %s\n' "$C_DIM" "$C_OFF" "$CURSOR_THEME" "$DEFAULT_INDEX"
    else
        printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_THEME" > "$DEFAULT_INDEX"
    fi
    ok "Default cursor set to $CURSOR_THEME."
fi

# Export XCURSOR_* before the session starts, so the WM sets it with no flash.
XSR="$HOME/.xsessionrc"
if [[ -f "$XSR" ]] && grep -q "^export XCURSOR_THEME=$CURSOR_THEME$" "$XSR"; then
    skip "~/.xsessionrc already exports XCURSOR_THEME."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would set:%s XCURSOR_THEME/SIZE → %s\n' "$C_DIM" "$C_OFF" "$XSR"
else
    touch "$XSR"
    sed -i '/^export XCURSOR_\(THEME\|SIZE\)=/d' "$XSR"
    printf 'export XCURSOR_THEME=%s\nexport XCURSOR_SIZE=24\n' "$CURSOR_THEME" >> "$XSR"
    ok "XCURSOR_* exported in ~/.xsessionrc (log out/in to apply)."
fi

# GTK apps read the cursor from gsettings separately.
if has_cmd gsettings; then
    run gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" \
        || warn "Could not set gsettings cursor-theme."
fi

ok "Fonts & cursor ready."
