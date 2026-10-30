#!/usr/bin/env bash
# The one file you edit per machine: settings.local, read once. Source after
# lib/common.sh. basic/95-settings.sh applies it; nothing else parses it.
#
# Sizes are NOT here — they are fonts.local's, next door, because they are the
# one thing that must differ per screen. Everything else this repo can decide
# for you lives in settings.local, and this file is how it gets read.

[[ -n "${_BLE_SETTINGS_LOADED:-}" ]] && return 0
_BLE_SETTINGS_LOADED=1

# The two files you edit (git-ignored, so per machine) and the tracked ones beside
# them: settings.local's template, and `aliases`, the aliases every machine gets.
BLE_SETTINGS_LOCAL="${BLE_SETTINGS_LOCAL:-$BLE_ROOT/settings.local}"
BLE_SETTINGS_EXAMPLE="${BLE_SETTINGS_EXAMPLE:-$BLE_ROOT/settings.local.example}"
BLE_ALIASES_LOCAL="${BLE_ALIASES_LOCAL:-$BLE_ROOT/aliases.local}"
BLE_ALIASES_SHARED="${BLE_ALIASES_SHARED:-$BLE_ROOT/aliases}"

# Every key settings.local may set. A key not set there stays empty, and the
# surface it drives keeps whatever its own config repo ships.
BLE_SETTING_KEYS=(
    BLE_EDITOR BLE_GIT_NAME BLE_GIT_EMAIL
    BLE_PROMPT_COLOR_USER BLE_PROMPT_COLOR_PATH
    BLE_CURSOR_COLOR BLE_I3_BORDER_COLOR BLE_I3_UNFOCUSED_COLOR
    BLE_I3_TITLEBAR BLE_FIREFOX_TITLEBAR BLE_I3_BAR BLE_I3_DESKTOP BLE_IDLE_POWEROFF
    BLE_TERMINAL_OPACITY BLE_BAR_COLOR BLE_TRACKPAD_SPEED
)

# Every key above that holds a yes/no. Normalised to true/false when the file is
# read, so a module tests one spelling and you may write any of the usual ones.
BLE_BOOL_KEYS=(BLE_I3_TITLEBAR BLE_FIREFOX_TITLEBAR BLE_IDLE_POWEROFF)

# Every key above that holds a colour: an xterm-256 number, or a #rrggbb you set. Validated together, rolled
# together, and written back into settings.local together — so adding a colour
# to a new surface is one line here and one write in basic/95-settings.sh.
BLE_COLOR_KEYS=(
    BLE_PROMPT_COLOR_USER BLE_PROMPT_COLOR_PATH
    BLE_CURSOR_COLOR BLE_I3_BORDER_COLOR BLE_I3_UNFOCUSED_COLOR
)
# The two i3 colours are rolled on a server too: tmux paints its session name
# and list highlight with them, and tmux runs everywhere.

# What each colour paints, for the comment written beside it in settings.local
# and for the list printed at the end of a run. One line per key above.
declare -A BLE_COLOR_WHAT=(
    [BLE_PROMPT_COLOR_USER]="user@host in the prompt"
    [BLE_PROMPT_COLOR_PATH]="the current folder in the prompt"
    [BLE_CURSOR_COLOR]="the terminal cursor"
    [BLE_I3_BORDER_COLOR]="the focused window in i3, the current workspace and tmux tab"
    [BLE_I3_UNFOCUSED_COLOR]="the unfocused windows in i3, tmux's session name"
)

BLE_EDITOR=""
BLE_GIT_NAME=""; BLE_GIT_EMAIL=""
BLE_PROMPT_COLOR_USER=""; BLE_PROMPT_COLOR_PATH=""
BLE_CURSOR_COLOR=""; BLE_I3_BORDER_COLOR=""; BLE_I3_UNFOCUSED_COLOR=""
BLE_I3_TITLEBAR=""; BLE_FIREFOX_TITLEBAR=""; BLE_I3_BAR=""; BLE_I3_DESKTOP=""; BLE_IDLE_POWEROFF=""
BLE_TERMINAL_OPACITY=""; BLE_BAR_COLOR=""; BLE_TRACKPAD_SPEED=""

# Keys that were settings once and no longer drive anything. Read silently, and
# settings_drop_retired takes their lines out of settings.local.
BLE_RETIRED_KEYS=(BLE_AGENT BLE_AGENT_DESK)

# _settings_known KEY  — true when KEY is one of the keys above.
_settings_known() {
    local k
    for k in "${BLE_SETTING_KEYS[@]}"; do [[ "$k" == "$1" ]] && return 0; done
    return 1
}

# settings_load  — parse settings.local into the variables above. Read as data,
# never sourced: a typo there must cost you one warned line, not the whole run.
settings_load() {
    [[ -r "$BLE_SETTINGS_LOCAL" ]] || return 0
    local line key value n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        # A '#' inside quotes is part of the value (an alias, a name); one that
        # starts the line, or follows whitespace, starts a comment.
        case "$line" in
            \#*) continue ;;
        esac
        line="${line%"${line##*[![:space:]]}"}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" != *=* ]]; then
            warn "settings.local line $n: expected KEY=VALUE — ignoring '$line'."
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        # Quotes are optional and dropped, so the file also reads as shell. They
        # are also how a value keeps a '#' — unquoted, a '#' starts a comment.
        case "$value" in
            \"*\"*) value="${value#\"}"; value="${value%%\"*}" ;;
            \'*\'*) value="${value#\'}"; value="${value%%\'*}" ;;
            *)      value="${value%%[[:space:]]#*}"
                    value="${value%"${value##*[![:space:]]}"}"
                    ;;
        esac

        [[ " ${BLE_RETIRED_KEYS[*]} " == *" $key "* ]] && continue
        if ! _settings_known "$key"; then
            warn "settings.local line $n: unknown key '$key' — ignoring it."
            continue
        fi
        printf -v "$key" '%s' "$value"
    done < "$BLE_SETTINGS_LOCAL"

    settings_validate
}

# settings_validate  — drop a value that would break the file it is written into.
# Every check here empties the key rather than stopping: one bad line must cost
# you that line, not the rest of your configuration.
settings_validate() {
    local k v

    # Every colour is written straight into an escape, a hex triplet or an i3
    # directive, where a word instead of a number paints your whole shell in a
    # stray colour code — or leaves i3 refusing to parse the line at all.
    for k in "${BLE_COLOR_KEYS[@]}"; do
        v="${!k}"
        [[ -z "$v" ]] && continue
        if [[ "$v" =~ ^#[0-9a-fA-F]{6}$ ]]; then
            printf -v "$k" '%s' "${v,,}"
        elif [[ ! "$v" =~ ^[0-9]+$ ]] || (( 10#$v > 255 )); then
            warn "settings.local: '$k=$v' is not a number 0-255 or a #rrggbb colour — ignoring it."
            printf -v "$k" '%s' ""
        fi
    done

    # A word that is neither yes nor no would land in an i3 border style or a
    # Firefox pref, where it means nothing and the surface simply misbehaves.
    for k in "${BLE_BOOL_KEYS[@]}"; do
        v="${!k}"
        [[ -z "$v" ]] && continue
        case "${v,,}" in
            true|yes|on|1)  printf -v "$k" '%s' true ;;
            false|no|off|0) printf -v "$k" '%s' false ;;
            *)  warn "settings.local: '$k=$v' is not true or false — ignoring it."
                printf -v "$k" '%s' "" ;;
        esac
    done

    # Which monitors the top bar opens on. The word is written into eww's
    # bar.local.conf, where anything but `all` or `main` leaves the bar as it was.
    if [[ -n "$BLE_I3_BAR" ]]; then
        case "${BLE_I3_BAR,,}" in
            all|both|every|everywhere) BLE_I3_BAR=all ;;
            main|primary|one)          BLE_I3_BAR=main ;;
            *)  warn "settings.local: 'BLE_I3_BAR=$BLE_I3_BAR' is not all or main — ignoring it."
                BLE_I3_BAR="" ;;
        esac
    fi

    # The i3 desktop mode, handed to ~/.i3rc/scripts/desktop_mode.sh as is.
    if [[ -n "$BLE_I3_DESKTOP" ]]; then
        case "${BLE_I3_DESKTOP,,}" in
            floating|float)       BLE_I3_DESKTOP=floating ;;
            tiling|tile|tiled)    BLE_I3_DESKTOP=tiling ;;
            *)  warn "settings.local: 'BLE_I3_DESKTOP=$BLE_I3_DESKTOP' is not floating or tiling — ignoring it."
                BLE_I3_DESKTOP="" ;;
        esac
    fi

    # Alacritty's window.opacity: a number from 0 (see-through) to 1 (solid).
    if [[ -n "$BLE_TERMINAL_OPACITY" && ! "$BLE_TERMINAL_OPACITY" =~ ^(0?\.[0-9]+|0|1|1\.0+)$ ]]; then
        warn "settings.local: 'BLE_TERMINAL_OPACITY=$BLE_TERMINAL_OPACITY' is not a number from 0 to 1 — ignoring it."
        BLE_TERMINAL_OPACITY=""
    fi

    # libinput's pointer speed for every touchpad: -1 (slowest) to 1 (fastest).
    if [[ -n "$BLE_TRACKPAD_SPEED" && ! "$BLE_TRACKPAD_SPEED" =~ ^-?(0|0?\.[0-9]+|1|1\.0+)$ ]]; then
        warn "settings.local: 'BLE_TRACKPAD_SPEED=$BLE_TRACKPAD_SPEED' is not a number from -1 to 1 — ignoring it."
        BLE_TRACKPAD_SPEED=""
    fi

    # The top bar's colour: the wallpaper's own, or a fixed #rrggbb.
    if [[ -n "$BLE_BAR_COLOR" ]]; then
        case "${BLE_BAR_COLOR,,}" in
            wallpaper|auto|match)  BLE_BAR_COLOR=wallpaper ;;
            \#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) BLE_BAR_COLOR="${BLE_BAR_COLOR,,}" ;;
            *)  warn "settings.local: 'BLE_BAR_COLOR=$BLE_BAR_COLOR' is not wallpaper or a #rrggbb colour — ignoring it."
                BLE_BAR_COLOR="" ;;
        esac
    fi

    # Equal colours are the one thing the prompt must never have: user@host and
    # the path would run together into one unreadable line. Compared as hex, so
    # 24 and #005f87 count as the same colour.
    if [[ -n "$BLE_PROMPT_COLOR_USER" && -n "$BLE_PROMPT_COLOR_PATH" &&
          "$(color_hex "$BLE_PROMPT_COLOR_USER")" == "$(color_hex "$BLE_PROMPT_COLOR_PATH")" ]]; then
        warn "settings.local: both prompt colours are $BLE_PROMPT_COLOR_USER — they must differ."
        warn "Dropping BLE_PROMPT_COLOR_PATH; a new one is rolled for you."
        BLE_PROMPT_COLOR_PATH=""
    fi

    # Same rule for the two i3 classes: painted alike, no window would tell you
    # which one has the keyboard, and that is the only reason they are coloured.
    if [[ -n "$BLE_I3_BORDER_COLOR" && -n "$BLE_I3_UNFOCUSED_COLOR" &&
          "$(color_hex "$BLE_I3_BORDER_COLOR")" == "$(color_hex "$BLE_I3_UNFOCUSED_COLOR")" ]]; then
        warn "settings.local: both i3 window colours are $BLE_I3_BORDER_COLOR — they must differ."
        warn "Dropping BLE_I3_UNFOCUSED_COLOR; a new one is rolled for you."
        BLE_I3_UNFOCUSED_COLOR=""
    fi

    # A newline would end the line it is written into early, and leave the rest
    # parsed as a line of its own.
    for k in BLE_EDITOR BLE_GIT_NAME BLE_GIT_EMAIL; do
        v="${!k}"
        if [[ "$v" == *$'\n'* ]]; then
            warn "settings.local: '$k' spans more than one line — ignoring it."
            printf -v "$k" '%s' ""
        fi
    done
}

# ── prompt colours ───────────────────────────────────────────────────────────
# The palette a fresh machine rolls from: twenty xterm-256 colours that stay
# readable on the dark terminal this repo installs, spread across six hues so
# any two picked out of it look different rather than merely differ by number.
BLE_PROMPT_PALETTE=(39 45 48 78 108 114 141 147 167 172 175 178 180 208 214 209 111 79 176 221)
BLE_PROMPT_PALETTE_NAME=(
    azure cyan "spring green" mint sage "light green" violet periwinkle red
    orange rose gold tan "bright orange" amber salmon "steel blue" teal orchid yellow
)

# color_name N  — the palette's word for a colour, its number when you chose
# one yourself, or the #rrggbb as written. Only ever used in a comment, so an
# unknown number is no error.
color_name() {
    local i
    [[ "$1" == \#* ]] && { printf '%s' "$1"; return 0; }
    for i in "${!BLE_PROMPT_PALETTE[@]}"; do
        [[ "${BLE_PROMPT_PALETTE[$i]}" == "$1" ]] && { printf '%s' "${BLE_PROMPT_PALETTE_NAME[$i]}"; return 0; }
    done
    printf 'colour %s' "$1"
}

# color_to256 C  — C as an xterm-256 number: a number stays itself, a #rrggbb
# becomes the nearest colour of the 6x6x6 cube or the grey ramp, whichever is
# closer. For a terminal with 256 colours but no truecolor, and for the 8-colour
# fallback below, which only knows numbers.
color_to256() {
    local c="$1" r g b ri gi bi cr cg cb grey gi_ d_cube d_grey i
    [[ "$c" == \#* ]] || { printf '%s' "$c"; return 0; }
    local cube=(0 95 135 175 215 255)
    r=$(( 16#${c:1:2} )); g=$(( 16#${c:3:2} )); b=$(( 16#${c:5:2} ))
    # Nearest cube step per channel: the steps are 0, then 95 + 40k.
    for i in r g b; do
        local v="${!i}" k
        if (( v < 48 )); then k=0; elif (( v < 115 )); then k=1; else k=$(( (v - 35) / 40 )); fi
        (( k > 5 )) && k=5
        printf -v "${i}i" '%s' "$k"
    done
    cr="${cube[$ri]}"; cg="${cube[$gi]}"; cb="${cube[$bi]}"
    d_cube=$(( (r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2 ))
    # Nearest grey of the ramp: 8 + 10n, n 0-23.
    gi_=$(( ((r + g + b) / 3 - 3) / 10 ))
    (( gi_ < 0 )) && gi_=0
    (( gi_ > 23 )) && gi_=23
    grey=$(( 8 + 10 * gi_ ))
    d_grey=$(( (r - grey) ** 2 + (g - grey) ** 2 + (b - grey) ** 2 ))
    if (( d_grey < d_cube )); then
        printf '%s' "$(( 232 + gi_ ))"
    else
        printf '%s' "$(( 16 + 36 * ri + 6 * gi + bi ))"
    fi
}

# color_fallback8 N  — the nearest of the eight ANSI colours (31-37), for a
# terminal with no 256-colour palette. The xterm cube is regular, so this is
# arithmetic rather than a table: split the index into r,g,b 0-5 and keep the
# channels at half brightness or more.
color_fallback8() {
    local n c r g b bits
    n="$(color_to256 "$1")"
    if (( n < 16 )); then
        # The sixteen basic colours are already ANSI ones; 8-15 are the bright
        # halves of the same eight.
        c=$(( n % 8 ))
        (( c == 0 )) && c=7     # black on a dark terminal is invisible
        printf '%s' "$(( 30 + c ))"
        return 0
    fi
    if (( n >= 232 )); then printf '37'; return 0; fi   # the grey ramp
    n=$(( n - 16 ))
    r=$(( n / 36 )); g=$(( n % 36 / 6 )); b=$(( n % 6 ))
    bits=0
    (( r >= 3 )) && bits=$(( bits + 4 ))
    (( g >= 3 )) && bits=$(( bits + 2 ))
    (( b >= 3 )) && bits=$(( bits + 1 ))
    case "$bits" in
        1) printf '34' ;;   # blue
        2) printf '32' ;;   # green
        3) printf '36' ;;   # cyan
        4) printf '31' ;;   # red
        5) printf '35' ;;   # magenta
        6) printf '33' ;;   # yellow
        *) printf '37' ;;   # white — and anything too dark to name
    esac
}

# color_zsh_name CODE  — the word zsh spells an ANSI code with, for the same
# fallback. zsh takes `%F{red}` on any terminal; `%F{208}` needs 256 colours.
color_zsh_name() {
    case "$1" in
        31) printf 'red' ;;     32) printf 'green' ;;   33) printf 'yellow' ;;
        34) printf 'blue' ;;    35) printf 'magenta' ;; 36) printf 'cyan' ;;
        *)  printf 'white' ;;
    esac
}

# color_hex N  — the rrggbb an xterm-256 number actually paints, with no prefix:
# i3 wants '#d787af' and Alacritty wants '0xd787af', so the caller adds its own.
# A #rrggbb you set is already that, and comes back without its '#'.
# The 16-231 cube is regular, so that range is arithmetic; the sixteen basic
# colours are a table nothing can derive, and 232-255 is an even grey ramp.
color_hex() {
    local n="$1" r g b
    local basic=(
        000000 800000 008000 808000 000080 800080 008080 c0c0c0
        808080 ff0000 00ff00 ffff00 0000ff ff00ff 00ffff ffffff
    )
    local cube=(0 95 135 175 215 255)
    [[ "$n" == \#* ]] && { printf '%s' "${n#\#}"; return 0; }
    if (( n < 16 )); then printf '%s' "${basic[$n]}"; return 0; fi
    if (( n >= 232 )); then
        r=$(( 8 + 10 * (n - 232) ))
        printf '%02x%02x%02x' "$r" "$r" "$r"
        return 0
    fi
    n=$(( n - 16 ))
    r="${cube[$(( n / 36 ))]}"; g="${cube[$(( n % 36 / 6 ))]}"; b="${cube[$(( n % 6 ))]}"
    printf '%02x%02x%02x' "$r" "$g" "$b"
}

# color_text_on N  — rrggbb for text painted ON colour N: white on a dark one,
# near-black on a light one. Perceived brightness 0-255, 128 is the middle.
color_text_on() {
    local hex r g b lum
    hex="$(color_hex "$1")"
    r=$(( 16#${hex:0:2} )); g=$(( 16#${hex:2:2} )); b=$(( 16#${hex:4:2} ))
    lum=$(( (299 * r + 587 * g + 114 * b) / 1000 ))
    if (( lum < 128 )); then printf 'ffffff'; else printf '1d2021'; fi
}

# color_swatch N  — a block painted in colour N, for a terminal that has colours;
# nothing on one that has not, so a log file does not fill with escapes.
color_swatch() {
    [[ -n "$C_OFF" ]] || return 0
    printf '\033[%sm    \033[0m' "$(color_sgr "$1" 48)"
}

# color_sgr C [38|48]  — the SGR parameters that paint C, foreground (38, the
# default) or background (48): '38;5;N' for a number, '38;2;R;G;B' for a #rrggbb.
color_sgr() {
    local c="$1" layer="${2:-38}"
    if [[ "$c" == \#* ]]; then
        printf '%s;2;%d;%d;%d' "$layer" "$(( 16#${c:1:2} ))" "$(( 16#${c:3:2} ))" "$(( 16#${c:5:2} ))"
    else
        printf '%s;5;%s' "$layer" "$c"
    fi
}

# settings_show_colors  — every colour, one per line, with its swatch, number,
# name and surface. What the end of a run prints so you can see what you got.
settings_show_colors() {
    local k
    for k in "${BLE_COLOR_KEYS[@]}"; do
        [[ -n "${!k}" ]] || continue
        printf '  %s %s%3s  %-13s %s%s\n' "$(color_swatch "${!k}")" "$C_DIM" \
            "${!k}" "$(color_name "${!k}")" "${BLE_COLOR_WHAT[$k]}" "$C_OFF"
    done
}

# settings_forget_colors  — drop every KEY= colour line (pinned ones too) and
# every "# Rolled by …" comment block from settings.local; nothing else moves.
settings_forget_colors() {
    local k keys="" tmp
    [[ -f "$BLE_SETTINGS_LOCAL" ]] || return 0
    for k in "${BLE_COLOR_KEYS[@]}"; do keys+="${keys:+|}$k"; done
    tmp="$(mktemp)"
    awk -v keys="^[[:space:]]*($keys)[[:space:]]*=" '
        /^# Rolled by best-linux-environment on / { skip = 1; next }
        skip && /^#/ { next }
        { skip = 0 }
        $0 ~ keys { next }
        /^[[:space:]]*$/ { if (blank) next; blank = 1; print; next }
        { blank = 0; print }
    ' "$BLE_SETTINGS_LOCAL" > "$tmp" && cat "$tmp" > "$BLE_SETTINGS_LOCAL"
    rm -f "$tmp"
    for k in "${BLE_COLOR_KEYS[@]}"; do printf -v "$k" '%s' ""; done
}

# roll_color KEY  — one colour out of the palette for KEY, when KEY has none yet.
# No pairing rule, unlike the prompt below: these land one to a surface, so there
# is nothing for them to have to look different from.
roll_color() {
    local n="${#BLE_PROMPT_PALETTE[@]}"
    [[ -n "${!1}" ]] && return 0
    printf -v "$1" '%s' "${BLE_PROMPT_PALETTE[RANDOM % n]}"
}

# roll_color_pair KEY_A KEY_B  — pick two, once, keeping whichever is set. They
# must differ in HUE, not only in number: two greens two shades apart read as one.
roll_color_pair() {
    local a="$1" b="$2" n="${#BLE_PROMPT_PALETTE[@]}" tries=0 pick

    while [[ -z "${!a}" ]]; do
        printf -v "$a" '%s' "${BLE_PROMPT_PALETTE[RANDOM % n]}"
    done

    while [[ -z "${!b}" ]]; do
        pick="${BLE_PROMPT_PALETTE[RANDOM % n]}"
        tries=$(( tries + 1 ))
        # Same colour: never, at any number of tries.
        [[ "$pick" == "${!a}" ]] && continue
        # Same hue family: refused while there is still room to look. After 50
        # tries take the different number — a pair that differs is the promise.
        if (( tries < 50 )) &&
           [[ "$(color_fallback8 "$pick")" == "$(color_fallback8 "${!a}")" ]]; then
            continue
        fi
        printf -v "$b" '%s' "$pick"
    done
}

settings_load
export "${BLE_SETTING_KEYS[@]}" BLE_SETTINGS_LOCAL BLE_ALIASES_LOCAL

# settings_seed  — settings.local from its example (LIVE values, a working base),
# and aliases.local as an empty file: the shared aliases are in `aliases`.
# Never overwrites an existing file.
settings_seed() {
    if [[ ! -f "$BLE_SETTINGS_EXAMPLE" ]]; then
        warn "$BLE_SETTINGS_EXAMPLE missing — cannot seed ${BLE_SETTINGS_LOCAL/#$HOME/\~}."
    else
        config_write "$BLE_SETTINGS_LOCAL" --if-missing < "$BLE_SETTINGS_EXAMPLE"
        if [[ "$CONFIG_WRITTEN" == true ]]; then
            ok "Edit ${BLE_SETTINGS_LOCAL/#$HOME/\~}, then re-run — every boot re-applies it."
        else
            settings_drop_retired; settings_fill
        fi
    fi

    if [[ ! -f "$BLE_ALIASES_LOCAL" ]]; then
        run touch "$BLE_ALIASES_LOCAL"
        ok "Created an empty ${BLE_ALIASES_LOCAL/#$HOME/\~} — this machine's own aliases go there."
    fi

    # Re-read: the file that was just written carries live values, and every
    # step after this one is entitled to see them on the very first run.
    settings_reload
    return 0
}

# settings_drop_retired  — delete the lines of BLE_RETIRED_KEYS from settings.local,
# commented-out ones too: nothing reads them any more.
settings_drop_retired() {
    local key found=()
    [[ -f "$BLE_SETTINGS_LOCAL" ]] || return 0
    for key in "${BLE_RETIRED_KEYS[@]}"; do
        grep -Eq "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "$BLE_SETTINGS_LOCAL" && found+=("$key")
    done
    [[ ${#found[@]} -eq 0 ]] && return 0

    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would remove:%s %s → %s\n' "$C_DIM" "$C_OFF" "${found[*]}" "${BLE_SETTINGS_LOCAL/#$HOME/\~}"
        return 0
    fi
    for key in "${found[@]}"; do
        sed -i -E "/^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=/d" "$BLE_SETTINGS_LOCAL"
    done
    ok "Removed from ${BLE_SETTINGS_LOCAL/#$HOME/\~}, no longer used: ${found[*]}."
}

# settings_fill  — append each live KEY= of the example that settings.local lacks,
# with its comments. A commented-out key counts as there: that is how you opt out.
settings_fill() {
    local key missing=() tmp
    [[ -f "$BLE_SETTINGS_LOCAL" && -f "$BLE_SETTINGS_EXAMPLE" ]] || return 0
    while IFS= read -r key; do
        grep -Eq "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "$BLE_SETTINGS_LOCAL" \
            || missing+=("$key")
    done < <(grep -oE '^BLE_[A-Z0-9_]+' "$BLE_SETTINGS_EXAMPLE" | awk '!seen[$0]++')
    [[ ${#missing[@]} -eq 0 ]] && return 0

    if [[ "$DRY_RUN" == true ]]; then
        for key in "${missing[@]}"; do
            printf '%s  would add:%s %s → %s\n' "$C_DIM" "$C_OFF" "$key" "${BLE_SETTINGS_LOCAL/#$HOME/\~}"
        done
        return 0
    fi

    # One example paragraph per missing key: its comments, and only the key lines
    # still missing, so a value you set is never repeated below it (the last wins).
    tmp="$(mktemp)"
    {
        printf '\n# Added by best-linux-environment on %s: new in settings.local.example.\n' "$(date '+%F')"
        printf '# Edit them as you like; comment one out to opt out (a deleted line comes back).\n\n'
        awk -v keys=" ${missing[*]} " '
            BEGIN { RS = "" }
            {
                n = split($0, line, "\n"); hit = 0
                for (i = 1; i <= n; i++) {
                    k = line[i]; sub(/=.*/, "", k)
                    if (line[i] ~ /^BLE_/ && index(keys, " " k " ")) hit = 1
                }
                if (!hit) next
                for (i = 1; i <= n; i++) {
                    k = line[i]; sub(/=.*/, "", k)
                    if (line[i] ~ /^#/ || index(keys, " " k " ")) print line[i]
                }
                print ""
            }
        ' "$BLE_SETTINGS_EXAMPLE"
    } > "$tmp"
    sed -i '$ { /^$/d }' "$tmp"
    cat "$tmp" >> "$BLE_SETTINGS_LOCAL"
    rm -f "$tmp"
    ok "Added to ${BLE_SETTINGS_LOCAL/#$HOME/\~}, new in the example: ${missing[*]}."
}

# settings_reload  — forget what was parsed and parse again. Only settings_seed
# needs it, after it created or added to settings.local.
settings_reload() {
    local k
    for k in "${BLE_SETTING_KEYS[@]}"; do printf -v "$k" '%s' ""; done
    settings_load
}

# ── the aliases: `aliases` (tracked, every machine) + aliases.local (this one) ─
# Older runs appended b-temp and fn to aliases.local and the <shell>-alias.local
# files; they live in `aliases` now, and aliases_retire takes those copies out.

# The exact blocks older runs appended: a comment pair, then the alias.
BLE_RETIRED_ALIASES=(
    '# CPU/GPU temperature logger (temperature-logger). Added by'
    '# best-linux-environment because this machine has temps installed.'
    'alias b-temp="temps"'
    '|'
    '# Quick scratch note: create/open ~/fastnote.txt in vim. Added by'
    '# best-linux-environment.'
    "alias fn='touch ~/fastnote.txt && vim ~/fastnote.txt'"
)

# aliases_retire  — drop those blocks from aliases.local and the <shell>-alias.local
# files. Lines of yours stay. Says what it removed.
aliases_retire() {
    local f block=() l
    for f in "$BLE_ALIASES_LOCAL" "$HOME/.zsh/zsh-alias.local" "$HOME/.bash/bash-alias.local"; do
        block=()
        for l in "${BLE_RETIRED_ALIASES[@]}" '|'; do
            if [[ "$l" != '|' ]]; then block+=("$l"); continue; fi
            aliases_drop "$f" "${block[@]}" && \
                ok "Removed ${block[-1]} from ${f/#$HOME/\~} — it is in ${BLE_ALIASES_SHARED/#$HOME/\~} now."
            block=()
        done
    done
    return 0
}

# aliases_drop FILE LINE...  — remove exactly these lines from FILE, and the
# blank line before the first one. Lines of yours stay. True
# when something was removed; --dry-run only prints what would go, and is false.
aliases_drop() {
    local f="$1"; shift
    local args=() l
    [[ -f "$f" ]] && grep -qxF "${!#}" "$f" || return 1
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would remove:%s %s from %s\n' "$C_DIM" "$C_OFF" "${!#}" "${f/#$HOME/\~}"
        return 1
    fi
    for l in "$@"; do args+=(-e "$l"); done
    awk -v c="$1" 'NR > 1 && !(prev == "" && $0 == c) { print prev } { prev = $0 }
        END { if (NR) print prev }' "$f" | grep -vxF "${args[@]}" > "$f.tmp" || true
    mv "$f.tmp" "$f"
}
