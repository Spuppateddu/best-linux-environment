#!/usr/bin/env bash
# The per-machine font sizes, read once from fonts.local. Source after
# lib/common.sh. basic/99-font-sizes.sh applies them; nothing else parses them.

[[ -n "${_BLE_FONTS_LOADED:-}" ]] && return 0
_BLE_FONTS_LOADED=1

# The one family of the whole desktop, installed by basic/50-fonts-cursor.sh. NF
# = the Nerd Font build: same face, plus the icon range the bar draws from.
BLE_FONT_FAMILY_TEXT="${BLE_FONT_FAMILY_TEXT:-Cascadia Code NF}"

# The file you edit on each PC. Git-ignored, so no machine's sizes reach another.
BLE_FONTS_LOCAL="${BLE_FONTS_LOCAL:-$BLE_ROOT/fonts.local}"

# Every key fonts.local may set, in the order fonts.local.example lists them.
# A key not set there stays empty, and its surface keeps the size its repo ships.
BLE_SIZE_KEYS=(
    BLE_SIZE_TERMINAL BLE_SIZE_I3 BLE_SIZE_BAR BLE_SIZE_ROFI BLE_SIZE_DUNST
    BLE_SIZE_GTK BLE_SIZE_FIREFOX_PAGE BLE_SIZE_FIREFOX_UI
)

BLE_SIZE_TERMINAL=""; BLE_SIZE_I3=""; BLE_SIZE_BAR=""; BLE_SIZE_ROFI=""
BLE_SIZE_DUNST=""; BLE_SIZE_GTK=""; BLE_SIZE_FIREFOX_PAGE=""; BLE_SIZE_FIREFOX_UI=""

# The size the greeter and GTK2 fall back to — the sizes above are overrides, so
# they are empty when unset, and these two surfaces are written on every run.
BLE_SIZE_GTK_DEFAULT=11

# _fonts_known KEY  — true when KEY is one of the keys above.
_fonts_known() {
    local k
    for k in "${BLE_SIZE_KEYS[@]}"; do [[ "$k" == "$1" ]] && return 0; done
    return 1
}

# fonts_load  — parse fonts.local into the variables above. Read as data, never
# sourced: a typo there must cost you one warned line, not the whole run.
fonts_load() {
    [[ -r "$BLE_FONTS_LOCAL" ]] || return 0
    local line key value n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" != *=* ]]; then
            warn "fonts.local line $n: expected KEY=VALUE — ignoring '$line'."
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        # Quotes are allowed round the number, so the file also reads as shell.
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"

        if ! _fonts_known "$key"; then
            warn "fonts.local line $n: unknown key '$key' — ignoring it."
            continue
        fi
        # Positive number, integer or decimal: everything downstream writes this
        # straight into a config file, where a stray word breaks the app quietly.
        if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$value" == 0 ]]; then
            warn "fonts.local line $n: '$key=$value' is not a positive number — ignoring it."
            continue
        fi
        printf -v "$key" '%s' "$value"
    done < "$BLE_FONTS_LOCAL"
}

# fonts_int KEY_VALUE OFFSET  — a size plus OFFSET, rounded to a whole number.
# The px sizes (eww, Firefox's chrome) have no use for the decimal alacritty takes.
fonts_int() {
    awk -v v="$1" -v o="${2:-0}" 'BEGIN { printf "%d", int(v + o + 0.5) }'
}

fonts_load
export BLE_FONT_FAMILY_TEXT BLE_FONTS_LOCAL "${BLE_SIZE_KEYS[@]}"
