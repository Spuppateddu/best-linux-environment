#!/usr/bin/env bash
# VLC — the video player, in the three places that must agree: yazi's Enter,
# xdg-open's video/* default, and the i3 border rule. Same shape as 57-image-viewer.sh.

# Without it yazi's preset sends a video to xdg-open, which has no video default
# and so picks whichever browser registered last — that is why .mp4 opened in Firefox.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Video player (VLC)"
require_desktop "VLC"

# ── 1. The package ───────────────────────────────────────────────────────────
# `vlc` is Ubuntu's metapackage: binary, Qt interface and codec plugins in one.
# mpv would be a third of the download; VLC is the one with a mouse-driven UI.
apt_ensure vlc

# ── 2. yazi: Enter on a video ────────────────────────────────────────────────
# %s, not "$@": yazi runs `run` in a shell with NO positional arguments, so "$@"
# is empty and VLC opens blank. %s is every selected file — one playlist.

# orphan = true or quitting yazi kills the player. `--` stops a filename that
# starts with `-` being read as a flag.

# 57 owns [opener] image, 75 owns [opener] pdf, this one owns [opener] video.
# All share the [open] array (TOML takes no second [open]), so we insert into it.
yazi_toml="$HOME/.config/yazi/yazi.toml"
VLC_RUN='vlc -- %s'
vlc_line=$'\t{ run = \''"$VLC_RUN"$'\', orphan = true, desc = "VLC", for = "unix" },'
video_key=$'video = [\n'"$vlc_line"$'\n]'
open_rule=$'\t{ mime = "video/*", use = "video" },'

# insert_after REGEX TEXT — put TEXT after the first matching line of yazi.toml.
# `cat >` and not `mv`, to keep the inode.
insert_after() {
    local re="$1" text="$2" tmp
    tmp="$(tmp_file .toml)"
    awk -v re="$re" -v text="$text" '
        { print }
        !inserted && $0 ~ re { print text; inserted = 1 }
    ' "$yazi_toml" > "$tmp"
    cat "$tmp" > "$yazi_toml"
    rm -f "$tmp"
}

if [[ ! -f "$yazi_toml" ]]; then
    step "Wiring the video opener into yazi.toml"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [opener] video + [open] rule → %s\n' \
            "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        printf '[opener]\n%s\n\n[open]\nprepend_rules = [\n%s\n]\n' "$video_key" "$open_rule" > "$yazi_toml"
    fi
    ok "yazi.toml → Enter on a video opens VLC."
else
    # ── 2a. the [opener] video key ────────────────────────────────────────────
    if grep -qF "$VLC_RUN" "$yazi_toml"; then
        skip "yazi.toml already opens videos in VLC."
    elif grep -q 'desc = "VLC"' "$yazi_toml"; then
        # Ours, from a version of this module that spelt the command differently.
        step "Pointing yazi's video opener at VLC"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would rewrite:%s [opener] video → %s → %s\n' \
                "$C_DIM" "$C_OFF" "$VLC_RUN" "${yazi_toml/#$HOME/\~}"
        else
            tmp="$(tmp_file .toml)"
            awk -v new="$vlc_line" '/desc = "VLC"/ { print new; next } { print }' \
                "$yazi_toml" > "$tmp"
            cat "$tmp" > "$yazi_toml"
            rm -f "$tmp"
        fi
        ok "yazi.toml → Enter on a video opens VLC."
    elif grep -Eq '^[[:space:]]*video[[:space:]]*=' "$yazi_toml"; then
        # Hand-written. A second video key is a duplicate, and yazi throws out
        # the WHOLE config over one.
        skip "yazi.toml has a video opener this repo did not write — left to you."
        skip "Point it at:  $VLC_RUN"
    elif grep -q '^\[opener\]' "$yazi_toml"; then
        step "Adding the video opener to yazi.toml"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would add:%s [opener] video → %s → %s\n' \
                "$C_DIM" "$C_OFF" "$VLC_RUN" "${yazi_toml/#$HOME/\~}"
        else
            insert_after '^\[opener\]' "$video_key"
        fi
        ok "yazi.toml → Enter on a video opens VLC."
    else
        step "Wiring the video opener into yazi.toml"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would append:%s [opener] video → %s\n' "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
        else
            [[ -s "$yazi_toml" ]] && printf '\n' >> "$yazi_toml"
            printf '[opener]\n%s\n' "$video_key" >> "$yazi_toml"
        fi
        ok "yazi.toml → Enter on a video opens VLC."
    fi

    # ── 2b. the [open] rule pointing video/* at that key ──────────────────────
    if grep -q 'mime = "video/\*"' "$yazi_toml"; then
        skip "yazi.toml already routes video/* to the video opener."
    elif grep -q '^prepend_rules = \[' "$yazi_toml"; then
        step "Routing video/* to the video opener"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would add:%s { mime = "video/*", use = "video" } → %s\n' \
                "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
        else
            insert_after '^prepend_rules = \[' "$open_rule"
        fi
        ok "yazi.toml → video/* uses the video opener."
    elif grep -q '^\[open\]' "$yazi_toml"; then
        # An [open] block written some other way. A second one is a duplicate
        # table, so stop rather than break the whole config.
        skip "yazi.toml has an [open] block this repo did not write — video rule left to you."
        skip 'Add to its rules:  { mime = "video/*", use = "video" }'
    else
        step "Routing video/* to the video opener"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would append:%s [open] prepend_rules (video/*) → %s\n' \
                "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
        else
            printf '\n[open]\nprepend_rules = [\n%s\n]\n' "$open_rule" >> "$yazi_toml"
        fi
        ok "yazi.toml → video/* uses the video opener."
    fi
fi

# Config errors are silent until launch, so parse-check what we just touched.
# </dev/null keeps yazi's "Press <Enter>" from blocking an install.
yazi_bin="$HOME/.local/bin/yazi"
has_cmd yazi && yazi_bin="yazi"
if [[ "$DRY_RUN" != true ]] && command -v "$yazi_bin" >/dev/null 2>&1; then
    if ! "$yazi_bin" --version </dev/null >/dev/null 2>&1; then
        warn "yazi rejects its config — it will start with preset settings. Details:"
        "$yazi_bin" --version </dev/null 2>&1 | sed 's/^/    /' || true
    fi
fi

# ── 3. i3: no title bar on the player ────────────────────────────────────────
# 08- sorts after 07-image-viewer.local and before config.local, which i3
# reads last — so a different border set there still wins.
CHANGED_I3=false
I3="$HOME/.i3rc"
I3_GEN="$I3/08-video-player.local"
i3_player_file() {
    printf '# Written by best-linux-environment — basic/58-video-player.sh.\n'
    printf '# Do NOT edit: every run rewrites it.\n'
    printf '#\n'
    printf '# config floats every window with `border normal 3`; on a player that is\n'
    printf '# only lost picture. Same rule and caveats as 07-image-viewer.local.\n'
    printf 'for_window [class="(?i)^vlc$"] border pixel 1\n'
}

if [[ ! -d "$I3" ]]; then
    skip "${I3/#$HOME/\~} not cloned yet — no i3 border rule to write (./setup.sh clones it)."
elif ! grep -Fq 'include ~/.i3rc/*.local' "$I3/config" 2>/dev/null; then
    warn "${I3/#$HOME/\~}/config does not include ~/.i3rc/*.local — pull that repo, the hook lives there."
else
    # write_gen: this repo owns the file whole. <<< and not a pipe, or
    # GEN_CHANGED comes back from a subshell unchanged.
    write_gen "$I3_GEN" <<< "$(i3_player_file)"
    CHANGED_I3="$GEN_CHANGED"

    if [[ -f "$I3/config.local" ]] && grep -Eq 'for_window .*[Vv]lc' "$I3/config.local"; then
        skip "~/.i3rc/config.local has its own vlc rule — that one is read last and wins."
    fi
fi

# ── 4. Everything else that opens a video ────────────────────────────────────
# xdg-open's default — a browser download, a mail attachment, a file manager.
# Ubuntu leaves this at whichever browser registered last.
if ! has_cmd xdg-mime; then
    warn "xdg-mime not found (xdg-utils) — system video default left as it is."
elif ! apt_installed vlc; then
    skip "vlc not installed — nothing to make the default yet."
else
    MIMES=(
        video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo
        video/mpeg video/x-flv video/x-ms-wmv video/3gpp video/ogg video/x-m4v
    )
    # Asked per type: xdg-mime answers one query at a time, and a partial
    # state is the normal one — the browser can hold video/webm alone.
    WRONG=()
    for m in "${MIMES[@]}"; do
        [[ "$(xdg-mime query default "$m" 2>/dev/null)" == "vlc.desktop" ]] || WRONG+=("$m")
    done

    if [[ ${#WRONG[@]} -eq 0 ]]; then
        skip "VLC is already the system default for every video type."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would set:%s vlc.desktop as default for %d type(s) — %s\n' \
            "$C_DIM" "$C_OFF" "${#WRONG[@]}" "${WRONG[*]}"
    else
        step "Making VLC the default for ${#WRONG[@]} video type(s)"
        # One call, not one per type: each is a rewrite of ~/.config/mimeapps.list.
        if xdg-mime default vlc.desktop "${WRONG[@]}" 2>/dev/null; then
            ok "xdg-open now opens videos in VLC."
        else
            warn "xdg-mime refused — ~/.config/mimeapps.list left as it is."
        fi
    fi
fi

# ── 5. Reload i3, so the rule applies without logging out ────────────────────
# Only when the file changed, and only when there is an i3 to talk to: the
# boot cron runs this module too, with no $DISPLAY.
if [[ "$CHANGED_I3" == true && "$DRY_RUN" != true && -n "${DISPLAY:-}" ]] \
   && has_cmd i3-msg && i3-msg -t get_version >/dev/null 2>&1; then
    i3-msg -q reload >/dev/null 2>&1 && ok "i3 reloaded — the player opens without a title bar." \
        || warn "Could not reload i3 — the rule applies at your next reload (\$mod+Shift+r)."
fi

ok "Video player ready — VLC."
