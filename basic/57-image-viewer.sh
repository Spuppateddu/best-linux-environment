#!/usr/bin/env bash
# nsxiv — the image viewer, and the three places that have to agree on it: yazi's
# Enter, xdg-open's image/* default, and the i3 rule that keeps its window from
# wearing a title bar. Plus the one libheif plugin Ubuntu leaves out, without
# which no HEIC opens anywhere on the machine.
#
# One owner for all three on purpose. The yazi opener used to live in 55-yazi.sh,
# back when it pointed at Firefox; two modules writing the same yazi.toml key is
# how it ends up disagreeing with itself.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Image viewer (nsxiv)"
require_desktop "nsxiv"

# ── 1. The packages ──────────────────────────────────────────────────────────
# nsxiv decodes through imlib2, whose heif.so loader calls libheif — and Ubuntu
# splits libheif's codecs into plugin packages, shipping only the AV1 pair
# (aomdec/aomenc). So AVIF works out of the box and HEIC does not, because a
# phone's .heic is HEVC. libde265 is that decoder, and it is the whole fix: it
# lands in /usr/lib/*/libheif/plugins and every libheif caller picks it up —
# nsxiv, GNOME's Loupe, gThumb, the file-manager thumbnailer. Without it a .heic
# looks like a broken viewer rather than a missing codec, since nothing says
# "no decoder" — the image simply fails to open.
apt_ensure nsxiv libheif-plugin-libde265

# ── 2. yazi: Enter on an image ───────────────────────────────────────────────
# %s, not "$@". yazi interpolates its own placeholders into `run` and then hands
# the result to a shell with NO positional arguments, so a "$@" written here is
# live shell syntax that expands to nothing — the viewer launches with no file
# and exits, which looks exactly like the key doing nothing. `yazi --version`
# does not catch it: the TOML is valid, only meaningless. The placeholders are
# %s (every selected file), %s1 (just the first) and %d1 (its parent dir) —
# `strings $(command -v yazi)` around "[opener]" is the authority for the
# version you have. %s rather than %s1 so selecting several images and pressing
# Enter opens them as one browsable set, which nsxiv takes and xdg-open cannot.
#
# orphan = true or quitting yazi takes the viewer with it. `-a` animates GIFs;
# `--` stops a filename that starts with `-` being read as a flag.
yazi_toml="$HOME/.config/yazi/yazi.toml"
nsxiv_run='nsxiv -a -- %s'
nsxiv_line=$'\t{ run = \''"$nsxiv_run"$'\', orphan = true, desc = "nsxiv", for = "unix" },'
opener_toml=$(cat <<TOML
[opener]
image = [
$nsxiv_line
]

[open]
prepend_rules = [
	{ mime = "image/*", use = "image" },
]
TOML
)

# Ours to rewrite when it carries either signature: the Firefox line 55-yazi.sh
# used to write, or an nsxiv line from a version of this module that still spelt
# the placeholder "$@". Anything else in [opener] was written by hand.
if [[ -f "$yazi_toml" ]] && grep -qF "$nsxiv_run" "$yazi_toml"; then
    skip "yazi.toml already opens images in nsxiv."
elif [[ -f "$yazi_toml" ]] && grep -Eq 'desc = "(Firefox|nsxiv)"' "$yazi_toml"; then
    step "Pointing yazi's image opener at nsxiv"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would rewrite:%s [opener] image → %s → %s\n' \
            "$C_DIM" "$C_OFF" "$nsxiv_run" "${yazi_toml/#$HOME/\~}"
    else
        tmp="$(tmp_file .toml)"
        awk -v new="$nsxiv_line" \
            '/desc = "Firefox"/ || /desc = "nsxiv"/ { print new; next } { print }' \
            "$yazi_toml" > "$tmp"
        cat "$tmp" > "$yazi_toml"
        rm -f "$tmp"
    fi
    ok "yazi.toml → Enter on an image opens nsxiv."
elif [[ -f "$yazi_toml" ]] && grep -q '^\[opener\]' "$yazi_toml"; then
    skip "yazi.toml has an [opener] block this repo did not write — image rule left to you."
    skip "Point its image entry at:  $nsxiv_run"
else
    step "Wiring the nsxiv image opener into yazi.toml"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would append:%s [opener]/[open] (images → nsxiv) → %s\n' "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        [[ -s "$yazi_toml" ]] && printf '\n' >> "$yazi_toml"
        printf '%s\n' "$opener_toml" >> "$yazi_toml"
    fi
    ok "yazi.toml → Enter on an image opens nsxiv."
fi

# ── 3. i3: no title bar on the viewer ────────────────────────────────────────
# 07- so it is read after 06-colors.local and before config.local, which i3
# reads last and which therefore still wins if you want a different width.
CHANGED_I3=false
I3="$HOME/.i3rc"
I3_GEN="$I3/07-image-viewer.local"
i3_viewer_file() {
    printf '# Written by best-linux-environment — basic/57-image-viewer.sh.\n'
    printf '# Do NOT edit: every run rewrites it.\n'
    printf '#\n'
    printf '# config floats every window with `border normal 3` — a real title bar you\n'
    printf '# can grab, which is right for an editor and wrong for a picture: the bar is\n'
    printf '# then the widest thing between you and the image. This drops the viewer to a\n'
    printf '# 1px edge. Still the focused colour 06-colors.local sets, still a mouse\n'
    printf '# resize handle, no title.\n'
    printf '#\n'
    printf '# It has to be a rule here rather than a `default_border`, because config sets\n'
    printf '# the border in the `for_window [class=".*"]` that floats everything, and this\n'
    printf '# file is read after it — the include is the last line of config.\n'
    printf '#\n'
    printf '# That only works while those are TWO rules in config:\n'
    printf '#   for_window [class=".*"] floating enable\n'
    printf '#   for_window [class=".*"] border normal 3\n'
    printf '# and NOT one chained `floating enable, border normal 3`. i3 re-runs the whole\n'
    printf '# assignment list from *inside* a command list, right after `floating enable`\n'
    printf '# finishes — so the chained form resumes afterwards and puts its own border\n'
    printf '# back over this one. Being read last is not enough. Nothing reports it; the\n'
    printf '# border simply never changes.\n'
    printf '#\n'
    printf '# Named 07-: config.local sorts after it, so\n'
    printf '#   for_window [class="(?i)^nsxiv$"] border none\n'
    printf '# there goes all the way to zero. 90-tiling-mode.local sorts after both, so\n'
    printf '# the tiling desktop is unaffected either way.\n'
    printf 'for_window [class="(?i)^nsxiv$"] border pixel 1\n'
}

if [[ ! -d "$I3" ]]; then
    skip "${I3/#$HOME/\~} not cloned yet — no i3 border rule to write (./setup.sh clones it)."
elif ! grep -Fq 'include ~/.i3rc/*.local' "$I3/config" 2>/dev/null; then
    warn "${I3/#$HOME/\~}/config does not include ~/.i3rc/*.local — pull that repo, the hook lives there."
else
    # write_gen, not config_write: this repo owns the file whole, so a changed
    # one is rewritten rather than backed up next to itself. <<< and not a pipe,
    # or GEN_CHANGED comes back from a subshell unchanged.
    write_gen "$I3_GEN" <<< "$(i3_viewer_file)"
    CHANGED_I3="$GEN_CHANGED"

    # The one thing that silently undoes this file: config.local is read after it.
    if [[ -f "$I3/config.local" ]] && grep -Eq 'for_window .*[Nn]sxiv' "$I3/config.local"; then
        skip "~/.i3rc/config.local has its own nsxiv rule — that one is read last and wins."
    fi

    # The other thing, and the one nobody would guess. i3 re-runs the whole
    # assignment list from *inside* a command list, right after `floating
    # enable` finishes — so a catch-all written as one chained command resumes
    # afterwards and puts its own border back over the rule above. Being read
    # last is not enough; the catch-all has to be two rules. Reported and not
    # patched: that file belongs to the i3 repo, and this module only writes
    # the *.local files beside it.
    if grep -Eq '^[[:space:]]*for_window \[class="\.\*"\].*floating enable[[:space:]]*,.*border' "$I3/config"; then
        warn "~/.i3rc/config chains 'floating enable, border ...' in its [class=\".*\"] rule."
        warn "While it does, NO per-app border rule can take effect — i3 re-runs assignments"
        warn "inside that command list, then resumes and puts the catch-all's border back."
        warn "Split it into two lines in the i3 repo, same order, nothing else changed:"
        warn '    for_window [class=".*"] floating enable'
        warn '    for_window [class=".*"] border normal 3'
    fi
fi

# ── 4. Everything else that opens an image ───────────────────────────────────
# xdg-open's default, which is what a browser download, a mail attachment or a
# desktop file manager hands an image to. Ubuntu leaves this pointing at
# whichever browser registered last, so a double-clicked photo opens a new tab.
#
# Raster only. SVG is deliberately not in the list: imlib2 rasterises it at one
# fixed size, and zooming in on the result gives you big blurry pixels, which is
# the opposite of the reason to have an SVG. That one stays with the browser.
if ! has_cmd xdg-mime; then
    warn "xdg-mime not found (xdg-utils) — system image default left as it is."
elif ! apt_installed nsxiv; then
    skip "nsxiv not installed — nothing to make the default yet."
else
    MIMES=(
        image/jpeg image/png image/gif image/bmp image/tiff image/webp
        image/heic image/heif image/avif image/jxl image/jp2
        image/x-xpixmap image/x-portable-pixmap
    )
    # Which ones do not already say nsxiv. Asked per type: xdg-mime reports one
    # answer per query, and a partial state is the normal one here — feh.desktop
    # had claimed image/heic while the browser held the rest.
    WRONG=()
    for m in "${MIMES[@]}"; do
        [[ "$(xdg-mime query default "$m" 2>/dev/null)" == "nsxiv.desktop" ]] || WRONG+=("$m")
    done

    if [[ ${#WRONG[@]} -eq 0 ]]; then
        skip "nsxiv is already the system default for every image type."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would set:%s nsxiv.desktop as default for %d type(s) — %s\n' \
            "$C_DIM" "$C_OFF" "${#WRONG[@]}" "${WRONG[*]}"
    else
        step "Making nsxiv the default for ${#WRONG[@]} image type(s)"
        # One call, not one per type: each is a rewrite of ~/.config/mimeapps.list.
        if xdg-mime default nsxiv.desktop "${WRONG[@]}" 2>/dev/null; then
            ok "xdg-open now opens images in nsxiv."
        else
            warn "xdg-mime refused — ~/.config/mimeapps.list left as it is."
        fi
    fi
fi

# ── 5. Reload i3, so the rule applies without logging out ────────────────────
# Only when the file actually changed, and only when there is an i3 to talk to:
# this module also runs from the boot cron, where there is no $DISPLAY.
if [[ "$CHANGED_I3" == true && "$DRY_RUN" != true && -n "${DISPLAY:-}" ]] \
   && has_cmd i3-msg && i3-msg -t get_version >/dev/null 2>&1; then
    i3-msg -q reload >/dev/null 2>&1 && ok "i3 reloaded — the viewer opens without a title bar." \
        || warn "Could not reload i3 — the rule applies at your next reload (\$mod+Shift+r)."
fi

ok "Image viewer ready — nsxiv, HEIC included."
