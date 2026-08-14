#!/usr/bin/env bash
# fonts.local into one override file per surface — the file each app reads LAST,
# so the config repos keep their own sizes and stay clean. See README § sizes.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Font sizes (fonts.local)"
require_desktop "Font sizes"
# After the title, so what fonts.local says about a typo of yours reads as part
# of this section rather than as a stray line above it.
source "$BLE_ROOT/lib/fonts.sh"

FAMILY="$BLE_FONT_FAMILY_TEXT"
CHANGED_I3=false CHANGED_BAR=false CHANGED_DUNST=false CHANGED_FIREFOX=false

if [[ -r "$BLE_FONTS_LOCAL" ]]; then
    step "Reading ${BLE_FONTS_LOCAL/#$HOME/\~}"
else
    skip "No fonts.local yet — every surface keeps the size its repo ships."
    skip "Start one:  cp fonts.local.example fonts.local"
fi

# ── writing ──────────────────────────────────────────────────────────────────
# write_gen DEST  — stdin into a file this repo owns whole. No backup is kept.
write_gen() {
    local dst="$1" new label; label="${dst/#$HOME/\~}"
    new="$(cat)"
    GEN_CHANGED=false
    if [[ -f "$dst" && "$new" == "$(cat "$dst" 2>/dev/null)" ]]; then
        skip "$label already up to date."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s %s\n' "$C_DIM" "$C_OFF" "$label"
    else
        mkdir -p "$(dirname "$dst")"
        printf '%s\n' "$new" > "$dst"
        ok "wrote $label"
    fi
    GEN_CHANGED=true
}

# drop_gen DEST OWNER  — the key is gone from fonts.local, so the override goes
# too and OWNER's own size applies again.
drop_gen() {
    local dst="$1" owner="$2" label="${1/#$HOME/\~}"
    GEN_CHANGED=false
    [[ -e "$dst" ]] || return 0
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would remove:%s %s\n' "$C_DIM" "$C_OFF" "$label"
    else
        rm -f "$dst"
        ok "removed $label — back to the size $owner ships."
    fi
    GEN_CHANGED=true
}

# hooked FILE NEEDLE  — true when the config repo's own file still names the
# override. Warned about rather than fixed: that file belongs to the other repo.
hooked() {
    [[ -f "$1" ]] || return 1
    grep -Fq "$2" "$1" && return 0
    warn "${1/#$HOME/\~} does not load $2 — pull that repo, the hook lives there."
    return 1
}

repo_here() {
    [[ -d "$1" ]] && return 0
    skip "${1/#$HOME/\~} not cloned yet — nothing to size (./setup.sh clones it)."
    return 1
}

# ── 1. Alacritty ─────────────────────────────────────────────────────────────
# The importing file wins here, so yours is the last import: size.local.toml.
ALA="$HOME/.alacritty"
if repo_here "$ALA" && hooked "$ALA/alacritty.toml" "size.local.toml"; then
    if [[ -n "$BLE_SIZE_TERMINAL" ]]; then
        write_gen "$ALA/size.local.toml" <<EOF
# Written by best-linux-environment — fonts.local, BLE_SIZE_TERMINAL.
[font]
size = $BLE_SIZE_TERMINAL
EOF
    else
        drop_gen "$ALA/size.local.toml" "~/.alacritty/size.toml"
    fi
fi

# ── 2. i3, and the three things i3 starts ────────────────────────────────────
# `include ~/.i3rc/*.local` reads this last; 05- keeps your config.local ahead.
I3="$HOME/.i3rc"
if repo_here "$I3"; then
    if hooked "$I3/config" 'include ~/.i3rc/*.local'; then
        if [[ -n "$BLE_SIZE_I3" ]]; then
            write_gen "$I3/05-fontsize.local" <<EOF
# Written by best-linux-environment — fonts.local, BLE_SIZE_I3.
font pango:$FAMILY $BLE_SIZE_I3
EOF
        else
            drop_gen "$I3/05-fontsize.local" "~/.i3rc/config"
        fi
        CHANGED_I3="$GEN_CHANGED"
    fi

    # The bar. Written even when the size is not set, because eww.scss imports it
    # unconditionally and a missing import is a compile error, not a shrug.
    if hooked "$I3/eww/eww.scss" "size.local.scss"; then
        if [[ -n "$BLE_SIZE_BAR" ]]; then
            write_gen "$I3/eww/size.local.scss" <<EOF
// Written by best-linux-environment — fonts.local, BLE_SIZE_BAR.
// Imported last by eww.scss, so these win on equal specificity.
* { font-size: $(fonts_int "$BLE_SIZE_BAR")px; }
.wsmon { font-size: $(fonts_int "$BLE_SIZE_BAR")px; }
.icon { font-size: $(fonts_int "$BLE_SIZE_BAR" 4)px; }
EOF
        else
            write_gen "$I3/eww/size.local.scss" <<'EOF'
// Written by best-linux-environment — fonts.local sets no BLE_SIZE_BAR, so the
// bar keeps eww.scss's own sizes. The file stays: eww.scss imports it.
EOF
        fi
        CHANGED_BAR="$GEN_CHANGED"
    fi

    # rofi: imported at the foot of both themes, where the last value wins. A
    # missing file is not an error there, so this one is removed when unset.
    if hooked "$I3/rofi/launcher.rasi" "size.local.rasi"; then
        if [[ -n "$BLE_SIZE_ROFI" ]]; then
            write_gen "$I3/rofi/size.local.rasi" <<EOF
/* Written by best-linux-environment — fonts.local, BLE_SIZE_ROFI. */
* { font: "$FAMILY $BLE_SIZE_ROFI"; }
EOF
        else
            drop_gen "$I3/rofi/size.local.rasi" "~/.i3rc/rofi"
        fi
    fi

    # dunst: i3 starts it with this as a second -config, and the later file wins.
    # Also not an error when missing.
    if hooked "$I3/config" "dunst/size.local.conf"; then
        if [[ -n "$BLE_SIZE_DUNST" ]]; then
            write_gen "$I3/dunst/size.local.conf" <<EOF
# Written by best-linux-environment — fonts.local, BLE_SIZE_DUNST.
[global]
font = $FAMILY $BLE_SIZE_DUNST
EOF
        else
            drop_gen "$I3/dunst/size.local.conf" "~/.i3rc/dunst/dunstrc"
        fi
        CHANGED_DUNST="$GEN_CHANGED"
    fi

    # GTK apps: CSS outranks settings.ini's gtk-font-name, and gtk.css imports
    # this first. Beside the symlink, not the repo file — that is where GTK looks.
    if hooked "$I3/gtk/gtk.css" "size.local.css"; then
        for gtk_dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
            # Written even when the size is unset, or every GTK app warns about
            # the missing import on every start.
            if [[ -n "$BLE_SIZE_GTK" ]]; then
                write_gen "$gtk_dir/size.local.css" <<EOF
/* Written by best-linux-environment — fonts.local, BLE_SIZE_GTK. */
* { font-size: ${BLE_SIZE_GTK}pt; }
EOF
            else
                write_gen "$gtk_dir/size.local.css" <<'EOF'
/* fonts.local sets no BLE_SIZE_GTK, so GTK keeps settings.ini's size. The file
   stays: gtk.css imports it either way. */
EOF
            fi
        done
    fi
fi

# ── 3. Firefox ───────────────────────────────────────────────────────────────
# The repo's install.sh appends user.local.js to user.js, where the last pref wins.
FF="$HOME/.firefox"
if repo_here "$FF" && hooked "$FF/install.sh" "user.local.js"; then
    if [[ -n "$BLE_SIZE_FIREFOX_PAGE" ]]; then
        write_gen "$FF/user.local.js" <<EOF
// Written by best-linux-environment — fonts.local, BLE_SIZE_FIREFOX_PAGE.
// Monospace keeps the +1 gap user.js holds, so code blocks match the body.
user_pref("font.size.variable.x-western", $(fonts_int "$BLE_SIZE_FIREFOX_PAGE"));
user_pref("font.size.monospace.x-western", $(fonts_int "$BLE_SIZE_FIREFOX_PAGE" 1));
EOF
    else
        drop_gen "$FF/user.local.js" "~/.firefox/user.js"
    fi
    CHANGED_FIREFOX="$GEN_CHANGED"

    if hooked "$FF/chrome/userChrome.css" "userChrome.local.css"; then
        if [[ -n "$BLE_SIZE_FIREFOX_UI" ]]; then
            write_gen "$FF/chrome/userChrome.local.css" <<EOF
/* Written by best-linux-environment — fonts.local, BLE_SIZE_FIREFOX_UI.
   userChrome.css reads this variable; without it, its own 12px stands. */
:root { --ble-ui-font-size: $(fonts_int "$BLE_SIZE_FIREFOX_UI")px; }
EOF
        else
            drop_gen "$FF/chrome/userChrome.local.css" "~/.firefox/chrome/userChrome.css"
        fi
        [[ "$GEN_CHANGED" == true ]] && CHANGED_FIREFOX=true
    fi
fi

# ── 4. Apply it to what is running ───────────────────────────────────────────
# Alacritty re-reads its imports itself; everything else is nudged here.
[[ "$DRY_RUN" == true ]] && { ok "Font sizes ready."; exit 0; }

if [[ -n "${DISPLAY:-}" ]] && has_cmd i3-msg && i3-msg -t get_version >/dev/null 2>&1; then
    if [[ "$CHANGED_I3" == true ]]; then
        i3-msg -q reload >/dev/null 2>&1 && ok "i3 reloaded." || warn "i3 reload failed."
    fi
    if [[ "$CHANGED_BAR" == true ]]; then
        EWW_BIN="$(command -v eww || echo "$HOME/.local/bin/eww")"
        if [[ -x "$EWW_BIN" ]]; then
            "$EWW_BIN" --config "$I3/eww" reload >/dev/null 2>&1 && ok "eww bar reloaded." \
                || skip "No eww bar running to reload."
        fi
    fi
    if [[ "$CHANGED_DUNST" == true ]] && has_cmd dunstctl; then
        dunstctl reload "$I3/dunst/dunstrc" "$I3/dunst/size.local.conf" >/dev/null 2>&1 \
            && ok "dunst reloaded." || skip "No dunst running to reload."
    fi
fi

# Firefox reads its prefs out of the profile, and only its own install.sh puts
# them there. Re-run for that one repo, and only when a size actually moved.
if [[ "$CHANGED_FIREFOX" == true && -x "$FF/install.sh" ]]; then
    step "Re-applying the Firefox config, so the new sizes reach the profile"
    bash "$BLE_ROOT/basic/10-tools.sh" firefox || warn "Could not re-apply ~/.firefox."
    warn "Restart Firefox to see it."
fi

ok "Font sizes ready."
