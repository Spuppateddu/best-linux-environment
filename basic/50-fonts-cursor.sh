#!/usr/bin/env bash
# The desktop's two fonts and the macOS cursor. Exclusive by design: JetBrainsMono
# becomes the one family, bar Cascadia Code, which section 4 lets through.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Fonts & cursor"
require_desktop "Fonts & cursor"
# The family below and the size the greeter and GTK2 render at both come from
# here, so fonts.local moves them without touching this file.
source "$BLE_ROOT/lib/fonts.sh"

# fonts-noto-core provides Noto Sans Symbols2, which section 5 and Alacritty's
# symbol rule both resolve fallback onto — so it is declared, not assumed.
apt_ensure fontconfig x11-xserver-utils fonts-noto-color-emoji fonts-noto-core

# ── 1. JetBrainsMono Nerd Font ───────────────────────────────────────────────
# Must be the Nerd Fonts build — apt's `fonts-jetbrains-mono` has no icon range.
FONT_DIR="$HOME/.local/share/fonts"
# All three builds, named once: the purge, the fontconfig rule and the GTK
# settings below must agree on the spelling or they silently pick another font.
FONT_FAMILY="JetBrainsMono Nerd Font"          # natural-width icons — the icon fallback
FONT_FAMILY_MONO="JetBrainsMono Nerd Font Mono"  # single-cell icons — terminal grid
FONT_FAMILY_PROPO="JetBrainsMono Nerd Font Propo" # proportional metrics — gtk/ui
# What i3, Alacritty and Firefox render text in, with JetBrainsMono behind it for
# icons. Installed in 1b, exempted in 4.
FONT_FAMILY_TEXT="$BLE_FONT_FAMILY_TEXT"
# With a size, for toolkits wanting a full description. The size is this machine's
# BLE_SIZE_GTK (fonts.local); its default, 11, is what ~/.i3rc renders at.
GTK_SIZE="${BLE_SIZE_GTK:-$BLE_SIZE_GTK_DEFAULT}"
UI_FONT="$FONT_FAMILY_TEXT $GTK_SIZE"
MONO_FONT="$FONT_FAMILY_MONO $GTK_SIZE"

# Never `fc-list | grep -q`: a SIGPIPE'd fc-list re-downloads the font every run.
# Match "JetBrainsMono Nerd", never bare "JetBrains Mono" — that one has no icons.
if compgen -G "$FONT_DIR/JetBrainsMono*Nerd*" >/dev/null 2>&1 \
   || fc-list 2>/dev/null | grep -iE "jetbrainsmono.*nerd" >/dev/null; then
    skip "JetBrainsMono Nerd Font already installed."
else
    url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    tmp="$(tmp_file .zip)"
    step "Installing JetBrainsMono Nerd Font"
    run mkdir -p "$FONT_DIR"
    # A condition, not run bare: an offline run would otherwise abort the module
    # and leave the half-downloaded temp file behind.
    if run curl -fL --progress-bar -o "$tmp" "$url" \
       && run unzip -oq "$tmp" -d "$FONT_DIR"; then
        # -r, not just -f: a plain `fc-cache -f` left the new files uncached, so
        # the icon range read as missing. -r drops the caches and rebuilds.
        run fc-cache -rf
        ok "JetBrainsMono Nerd Font installed."
    else
        warn "Could not install the JetBrainsMono Nerd Font — icons will be missing until a later run."
    fi
    run rm -f "$tmp"
fi

# ── 1b. Cascadia Code ────────────────────────────────────────────────────────
# The four statics, not the variable build: only they report style=Bold/Italic.
CASCADIA_VERSION="2407.24"
CASCADIA_GLOB="CascadiaCode-*"   # section 2 reuses it to spare these from the sweep
if compgen -G "$FONT_DIR/$CASCADIA_GLOB" >/dev/null 2>&1; then
    skip "$FONT_FAMILY_TEXT already installed."
else
    url="https://github.com/microsoft/cascadia-code/releases/download/v$CASCADIA_VERSION/CascadiaCode-$CASCADIA_VERSION.zip"
    tmp="$(tmp_file .zip)"
    step "Installing $FONT_FAMILY_TEXT $CASCADIA_VERSION"
    run mkdir -p "$FONT_DIR"
    # A condition, like the Nerd Font above. -j flattens ttf/static/ away, and
    # naming the four files keeps the NF and PL variants out of $FONT_DIR.
    if run curl -fL --progress-bar -o "$tmp" "$url" \
       && run unzip -oqj "$tmp" \
              'ttf/static/CascadiaCode-Regular.ttf' 'ttf/static/CascadiaCode-Bold.ttf' \
              'ttf/static/CascadiaCode-Italic.ttf' 'ttf/static/CascadiaCode-BoldItalic.ttf' \
              -d "$FONT_DIR"; then
        run fc-cache -rf
        ok "$FONT_FAMILY_TEXT installed."
    else
        warn "Could not install $FONT_FAMILY_TEXT — i3, Alacritty and Firefox will fall back to JetBrainsMono until a later run."
    fi
    run rm -f "$tmp"
fi

# ── 2. Every other user-installed font removed ───────────────────────────────
# User dirs only, and guarded on the font being present, or nothing would be left.
if compgen -G "$FONT_DIR/JetBrainsMono*Nerd*" >/dev/null 2>&1; then
    # -print0/read -d: font filenames from a zip can carry spaces.
    others=()
    while IFS= read -r -d '' f; do others+=("$f"); done < <(
        find "$FONT_DIR" "$HOME/.fonts" -type f \
             \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \
                -o -iname '*.pfb' -o -iname '*.pcf*' -o -iname '*.woff*' \) \
             ! -iname 'JetBrainsMono*' ! -iname "$CASCADIA_GLOB" -print0 2>/dev/null
    )
    if [[ ${#others[@]} -eq 0 ]]; then
        skip "No other user-installed fonts to remove."
    else
        step "Removing ${#others[@]} other user-installed font file(s)"
        for f in "${others[@]}"; do
            printf '%s    %s%s\n' "$C_DIM" "${f/#$HOME/\~}" "$C_OFF"
        done
        run rm -f "${others[@]}"
        # Directories the removed families came in; -empty so a dir still holding
        # JetBrainsMono files stays.
        run find "$FONT_DIR" "$HOME/.fonts" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        run fc-cache -rf
        ok "Other user-installed fonts removed."
    fi
else
    skip "JetBrainsMono not on disk — leaving other fonts alone."
fi

# ── 3. The login screen ──────────────────────────────────────────────────────
# The greeter cannot read $HOME, so it needs a copy in /usr/local/share/fonts.
SYS_FONT_DIR="/usr/local/share/fonts/jetbrains-mono-nerd-font"
GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"

if ! apt_installed lightdm-gtk-greeter; then
    skip "LightDM GTK greeter not installed — skipping the system font copy."
else
    # Count-compare, so a half-copied directory doesn't look done forever. Both
    # sides via process substitution: `find | wc -l` exits the module on run one.
    sys_src=(); while IFS= read -r -d '' f; do sys_src+=("$f"); done < <(
        find "$FONT_DIR" -maxdepth 1 -name 'JetBrainsMono*.ttf' -print0 2>/dev/null)
    sys_have=(); while IFS= read -r -d '' f; do sys_have+=("$f"); done < <(
        find "$SYS_FONT_DIR" -maxdepth 1 -name 'JetBrainsMono*.ttf' -print0 2>/dev/null)

    if [[ ${#sys_src[@]} -eq 0 ]]; then
        skip "JetBrainsMono not on disk — nothing to copy system-wide."
    elif [[ ${#sys_have[@]} -eq ${#sys_src[@]} ]]; then
        skip "JetBrainsMono already installed system-wide."
    elif [[ "$DRY_RUN" != true ]] && ! can_sudo; then
        warn "sudo unavailable — login screen left on the distro font."
    else
        step "Installing JetBrainsMono system-wide for the login screen"
        run sudo mkdir -p "$SYS_FONT_DIR"
        run sudo cp -f "${sys_src[@]}" "$SYS_FONT_DIR/"
        # cp preserves the umask of whoever ran the installer; the greeter has to
        # be able to read these.
        run sudo chmod 644 "$SYS_FONT_DIR"/JetBrainsMono*.ttf
        run sudo fc-cache -f "$SYS_FONT_DIR"
        ok "JetBrainsMono installed system-wide."
    fi

    # Ships commented out, so this writes the line rather than editing one —
    # under [greeter], the only section it is read from.
    if [[ ! -f "$GREETER_CONF" ]]; then
        warn "$GREETER_CONF missing — login screen font not set."
    elif grep -qxF "font-name=$UI_FONT" "$GREETER_CONF"; then
        skip "Login screen font already $UI_FONT."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would set:%s font-name=%s → %s\n' "$C_DIM" "$C_OFF" "$UI_FONT" "$GREETER_CONF"
    elif ! can_sudo; then
        warn "sudo unavailable — login screen font not set."
    else
        step "Setting the login screen font"
        # Delete any previous value first, so re-runs replace instead of stacking.
        sudo sed -i -e '/^font-name=/d' -e "\\|^\\[greeter\\]|a font-name=$UI_FONT" \
            "$GREETER_CONF"
        ok "Login screen font set to $UI_FONT."
    fi
fi

# ── 4. JetBrainsMono as the default for every family ─────────────────────────
# prepend_first + strong, never <alias><prefer>; not_eq qual="all" is the exception list.
JB_CONF="$HOME/.config/fontconfig/conf.d/60-jetbrainsmono-default.conf"
config_write "$JB_CONF" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Written by best-linux-environment/basic/50-fonts-cursor.sh.
     One family for the whole desktop; see that script for the reasoning. -->
<fontconfig>

  <!-- Every request, generic or by name, except the families listed here, which
       must reach their own font. Propo = proportional metrics, for UI and text. -->
  <match target="pattern">
    <test name="family" compare="not_eq" qual="all"><string>$FONT_FAMILY</string></test>
    <test name="family" compare="not_eq" qual="all"><string>$FONT_FAMILY_MONO</string></test>
    <test name="family" compare="not_eq" qual="all"><string>$FONT_FAMILY_PROPO</string></test>
    <test name="family" compare="not_eq" qual="all"><string>$FONT_FAMILY_TEXT</string></test>
    <test name="family" compare="not_eq" qual="all"><string>Noto Color Emoji</string></test>
    <test name="family" compare="not_eq" qual="all"><string>Noto Sans Symbols2</string></test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$FONT_FAMILY_PROPO</string>
    </edit>
  </match>

  <!-- Anything fixed-width takes the Mono build, whose icons fit one cell. The
       second test keeps the desktop's text font out of it, whatever 45-latin says. -->
  <match target="pattern">
    <test name="family" compare="eq" qual="any"><string>monospace</string></test>
    <test name="family" compare="not_eq" qual="all"><string>$FONT_FAMILY_TEXT</string></test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$FONT_FAMILY_MONO</string>
    </edit>
  </match>

</fontconfig>
XML
if [[ "$CONFIG_WRITTEN" == true ]]; then
    run fc-cache -rf
    ok "$FONT_FAMILY is the default family; $FONT_FAMILY_TEXT reaches the apps that name it."
    warn "Restart running apps (or log out) to pick up the new default font."
fi

# ── 5. Colour emoji over monochrome symbols ──────────────────────────────────
# Symbols2 outranks Color Emoji for U+1F7E0/1; a weak append fixes it harmlessly.
EMOJI_CONF="$HOME/.config/fontconfig/conf.d/75-prefer-color-emoji.conf"
config_write "$EMOJI_CONF" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="pattern">
    <edit name="family" mode="append" binding="weak">
      <string>Noto Color Emoji</string>
    </edit>
  </match>
</fontconfig>
XML
# Its own fc-cache: the one above only fires on a fresh download. Only after an
# actual write, or every boot would rebuild the font caches.
if [[ "$CONFIG_WRITTEN" == true ]]; then
    run fc-cache -f
    ok "Colour emoji preferred in font fallback."
fi

# ── 6. GTK / GNOME font settings ─────────────────────────────────────────────
# gsettings for GNOME apps, gtkrc-2.0 for GTK2; GTK3/4's ini belongs to ~/.i3rc.

if has_cmd gsettings; then
    gtk_font_changed=false
    # document-font-name is what Evince/Nautilus use for body text, and it
    # defaults to a different family than font-name.
    for pair in "font-name=$UI_FONT" "document-font-name=$UI_FONT" \
                "monospace-font-name=$MONO_FONT"; do
        key="${pair%%=*}"; value="${pair#*=}"
        # gsettings get quotes its output; compare against the quoted form.
        if [[ "$(gsettings get org.gnome.desktop.interface "$key" 2>/dev/null)" == "'$value'" ]]; then
            skip "gsettings $key already $value."
        else
            run gsettings set org.gnome.desktop.interface "$key" "$value" \
                && gtk_font_changed=true \
                || warn "Could not set gsettings $key."
        fi
    done
    [[ "$gtk_font_changed" == true ]] && ok "GTK/GNOME fonts set to $FONT_FAMILY."
fi

# GTK2. Rewritten in place, not appended, so re-runs replace the line rather
# than stacking duplicates.
GTKRC2="$HOME/.gtkrc-2.0"
if [[ -f "$GTKRC2" ]] && grep -qxF "gtk-font-name=\"$UI_FONT\"" "$GTKRC2"; then
    skip "GTK2 font already $UI_FONT."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would set:%s gtk-font-name="%s" → %s\n' "$C_DIM" "$C_OFF" "$UI_FONT" "$GTKRC2"
else
    step "Setting the GTK2 font"
    touch "$GTKRC2"
    sed -i '/^gtk-font-name=/d' "$GTKRC2"
    printf 'gtk-font-name="%s"\n' "$UI_FONT" >> "$GTKRC2"
    ok "GTK2 font set to $UI_FONT."
fi

# ── 7. macOS cursor ──────────────────────────────────────────────────────────
# Must live under ~/.icons: libXcursor's search path excludes .local/share/icons.
CURSOR_THEME="macOS"
CURSOR_VERSION="v2.0.1"
CURSOR_DIR="$HOME/.icons/$CURSOR_THEME"

if [[ -d "$CURSOR_DIR" ]]; then
    skip "$CURSOR_THEME cursor already installed."
else
    url="https://github.com/ful1e5/apple_cursor/releases/download/$CURSOR_VERSION/macOS.tar.xz"
    tmp="$(tmp_file .tar.xz)"
    step "Installing $CURSOR_THEME cursor ($CURSOR_VERSION)"
    run mkdir -p "$HOME/.icons"
    # As with the font above: a failed download must not take the XCURSOR_*
    # exports and the gsettings call at the end of the module with it.
    if run curl -fL --progress-bar -o "$tmp" "$url" \
       && run tar -xf "$tmp" -C "$HOME/.icons"; then
        ok "$CURSOR_THEME cursor installed."
    else
        warn "Could not install the $CURSOR_THEME cursor — the default pointer stays for now."
    fi
    run rm -f "$tmp"
fi

# The X11 default, since i3 has no settings GUI. Seeded, not managed: picking
# another cursor by hand is normal, so only ./setup.sh puts macOS back.
DEFAULT_INDEX="$HOME/.icons/default/index.theme"
config_write "$DEFAULT_INDEX" --seed <<EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF

# Export XCURSOR_* before the session starts, so the WM sets it with no flash.
xsessionrc_export XCURSOR_THEME "$CURSOR_THEME"
theme_changed="$XSESSIONRC_CHANGED"
xsessionrc_export XCURSOR_SIZE 24
if [[ "$theme_changed" == true || "$XSESSIONRC_CHANGED" == true ]]; then
    warn "Log out and back in to apply XCURSOR_*."
fi

# GTK apps read the cursor from gsettings separately.
if has_cmd gsettings; then
    run gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" \
        || warn "Could not set gsettings cursor-theme."
fi

ok "Fonts & cursor ready."
