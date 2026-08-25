#!/usr/bin/env bash
# The one file you edit per machine: settings.local, read once. Source after
# lib/common.sh. basic/95-settings.sh applies it; nothing else parses it.
#
# Sizes are NOT here — they are fonts.local's, next door, because they are the
# one thing that must differ per screen. Everything else this repo can decide
# for you lives in settings.local, and this file is how it gets read.

[[ -n "${_BLE_SETTINGS_LOADED:-}" ]] && return 0
_BLE_SETTINGS_LOADED=1

# The two files you edit, and the two committed templates they are seeded from.
# Git-ignored, so no machine's answers reach another through a push.
BLE_SETTINGS_LOCAL="${BLE_SETTINGS_LOCAL:-$BLE_ROOT/settings.local}"
BLE_SETTINGS_EXAMPLE="$BLE_ROOT/settings.local.example"
BLE_ALIASES_LOCAL="${BLE_ALIASES_LOCAL:-$BLE_ROOT/aliases.local}"
BLE_ALIASES_EXAMPLE="$BLE_ROOT/aliases.local.example"

# Every key settings.local may set. A key not set there stays empty, and the
# surface it drives keeps whatever its own config repo ships.
BLE_SETTING_KEYS=(
    BLE_AGENT BLE_AGENT_DESK BLE_EDITOR BLE_GIT_NAME BLE_GIT_EMAIL
    BLE_PROMPT_COLOR_USER BLE_PROMPT_COLOR_PATH
    BLE_CURSOR_COLOR BLE_I3_BORDER_COLOR
)

# Every key above that holds an xterm-256 colour. Validated together, rolled
# together, and written back into settings.local together — so adding a colour
# to a new surface is one line here and one write in basic/95-settings.sh.
BLE_COLOR_KEYS=(
    BLE_PROMPT_COLOR_USER BLE_PROMPT_COLOR_PATH
    BLE_CURSOR_COLOR BLE_I3_BORDER_COLOR
)

BLE_AGENT=""; BLE_AGENT_DESK=""; BLE_EDITOR=""
BLE_GIT_NAME=""; BLE_GIT_EMAIL=""
BLE_PROMPT_COLOR_USER=""; BLE_PROMPT_COLOR_PATH=""
BLE_CURSOR_COLOR=""; BLE_I3_BORDER_COLOR=""

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
        if [[ ! "$v" =~ ^[0-9]+$ ]] || (( v > 255 )); then
            warn "settings.local: '$k=$v' is not a number 0-255 — ignoring it."
            printf -v "$k" '%s' ""
        fi
    done

    # Equal colours are the one thing the prompt must never have: user@host and
    # the path would run together into one unreadable line.
    if [[ -n "$BLE_PROMPT_COLOR_USER" && "$BLE_PROMPT_COLOR_USER" == "$BLE_PROMPT_COLOR_PATH" ]]; then
        warn "settings.local: both prompt colours are $BLE_PROMPT_COLOR_USER — they must differ."
        warn "Dropping BLE_PROMPT_COLOR_PATH; a new one is rolled for you."
        BLE_PROMPT_COLOR_PATH=""
    fi

    # i3 starts the agent with no shell, so ~ is ours to expand, and a relative
    # path is meaningless there: i3's own cwd is whatever it was started from.
    if [[ -n "$BLE_AGENT_DESK" ]]; then
        case "$BLE_AGENT_DESK" in
            '~'|'$HOME')  BLE_AGENT_DESK="$HOME" ;;
            '~/'*)        BLE_AGENT_DESK="$HOME/${BLE_AGENT_DESK#\~/}" ;;
            '$HOME/'*)    BLE_AGENT_DESK="$HOME/${BLE_AGENT_DESK#\$HOME/}" ;;
        esac
        if [[ "$BLE_AGENT_DESK" != /* ]]; then
            warn "settings.local: BLE_AGENT_DESK='$BLE_AGENT_DESK' is not an absolute path — ignoring it."
            BLE_AGENT_DESK=""
        fi
    fi

    # A newline would end the `set \$agent` line early and leave i3 parsing the
    # rest as a directive of its own.
    for k in BLE_AGENT BLE_EDITOR BLE_GIT_NAME BLE_GIT_EMAIL; do
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

# color_name N  — the palette's word for a colour, or its number when you chose
# one yourself. Only ever used in a comment, so an unknown number is no error.
color_name() {
    local i
    for i in "${!BLE_PROMPT_PALETTE[@]}"; do
        [[ "${BLE_PROMPT_PALETTE[$i]}" == "$1" ]] && { printf '%s' "${BLE_PROMPT_PALETTE_NAME[$i]}"; return 0; }
    done
    printf 'colour %s' "$1"
}

# color_fallback8 N  — the nearest of the eight ANSI colours (31-37), for a
# terminal with no 256-colour palette. The xterm cube is regular, so this is
# arithmetic rather than a table: split the index into r,g,b 0-5 and keep the
# channels at half brightness or more.
color_fallback8() {
    local n="$1" c r g b bits
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
# The 16-231 cube is regular, so that range is arithmetic; the sixteen basic
# colours are a table nothing can derive, and 232-255 is an even grey ramp.
color_hex() {
    local n="$1" r g b
    local basic=(
        000000 800000 008000 808000 000080 800080 008080 c0c0c0
        808080 ff0000 00ff00 ffff00 0000ff ff00ff 00ffff ffffff
    )
    local cube=(0 95 135 175 215 255)
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

# roll_color KEY  — one colour out of the palette for KEY, when KEY has none yet.
# No pairing rule, unlike the prompt below: these land one to a surface, so there
# is nothing for them to have to look different from.
roll_color() {
    local n="${#BLE_PROMPT_PALETTE[@]}"
    [[ -n "${!1}" ]] && return 0
    printf -v "$1" '%s' "${BLE_PROMPT_PALETTE[RANDOM % n]}"
}

# roll_prompt_colors  — pick the two, once. Sets BLE_PROMPT_COLOR_USER and
# BLE_PROMPT_COLOR_PATH, keeping whichever is already set. The pair must differ
# in HUE, not only in number: two greens two shades apart read as one colour, and
# telling the machine from the path is the whole reason for colouring them.
roll_prompt_colors() {
    local n="${#BLE_PROMPT_PALETTE[@]}" tries=0 pick

    while [[ -z "$BLE_PROMPT_COLOR_USER" ]]; do
        BLE_PROMPT_COLOR_USER="${BLE_PROMPT_PALETTE[RANDOM % n]}"
    done

    while [[ -z "$BLE_PROMPT_COLOR_PATH" ]]; do
        pick="${BLE_PROMPT_PALETTE[RANDOM % n]}"
        tries=$(( tries + 1 ))
        # Same colour: never, at any number of tries.
        [[ "$pick" == "$BLE_PROMPT_COLOR_USER" ]] && continue
        # Same hue family: refused while there is still room to look. After 50
        # tries take the different number — a pair that differs is the promise.
        if (( tries < 50 )) &&
           [[ "$(color_fallback8 "$pick")" == "$(color_fallback8 "$BLE_PROMPT_COLOR_USER")" ]]; then
            continue
        fi
        BLE_PROMPT_COLOR_PATH="$pick"
    done
}

settings_load
export "${BLE_SETTING_KEYS[@]}" BLE_SETTINGS_LOCAL BLE_ALIASES_LOCAL

# agent_installed CMD  — is this agent actually on the machine? PATH, ~/.local/bin
# (the boot cron's PATH has neither) or opencode's own ~/.opencode/bin.
agent_installed() {
    has_cmd "$1" || have_local_bin "$1" || { [[ "$1" == opencode ]] && have_opencode_bin; }
}

# pick_agent  — the first agent that is actually here, in preference order.
# Prints nothing when none of them is, and the seeded default then stands so the
# file still shows you the shape of the answer.
pick_agent() {
    local a
    for a in claude opencode codex; do
        agent_installed "$a" && { printf '%s' "$a"; return 0; }
    done
    return 1
}

# settings_seed  — put the two files there when they are not, straight from the
# committed examples. Their values are LIVE, not commented-out examples: a fresh
# machine is supposed to start from a working base, not from a blank file you
# have to fill in before anything happens. Never overwrites an existing file.
settings_seed() {
    local pair dst src

    for pair in "$BLE_SETTINGS_LOCAL|$BLE_SETTINGS_EXAMPLE" \
                "$BLE_ALIASES_LOCAL|$BLE_ALIASES_EXAMPLE"; do
        dst="${pair%%|*}"; src="${pair##*|}"
        if [[ ! -f "$src" ]]; then
            warn "$src missing — cannot seed ${dst/#$HOME/\~}."
            continue
        fi
        config_write "$dst" --if-missing < "$src"
        [[ "$CONFIG_WRITTEN" != true ]] && continue

        # Only for the file that names an agent, and only on the run that
        # created it: after that the value is yours, and a later run must not
        # move it because you happened to install something else.
        if [[ "$dst" == "$BLE_SETTINGS_LOCAL" && "$DRY_RUN" != true ]]; then
            local found
            if found="$(pick_agent)"; then
                if [[ "$found" != claude ]]; then
                    sed -i "s|^BLE_AGENT=claude\$|BLE_AGENT=$found|" "$dst"
                    ok "Agent on this machine: $found — set as BLE_AGENT for you."
                fi
            else
                warn "No coding agent found (claude, opencode, codex) — BLE_AGENT stays 'claude'."
                warn "Install one, or change BLE_AGENT in ${dst/#$HOME/\~}."
            fi
        fi

        ok "Edit ${dst/#$HOME/\~}, then re-run — every boot re-applies it."
    done

    # Re-read: the file that was just written carries live values, and every
    # step after this one is entitled to see them on the very first run.
    settings_reload
    return 0
}

# settings_reload  — forget what was parsed and parse again. Only settings_seed
# needs it, and only on the run that created the file.
settings_reload() {
    local k
    for k in "${BLE_SETTING_KEYS[@]}"; do printf -v "$k" '%s' ""; done
    settings_load
}
