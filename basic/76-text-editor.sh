#!/usr/bin/env bash
# Text editor default — vim, in the two places that decide what opens a text
# file: yazi's Enter and xdg-open. Installs nothing itself.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Text editor default (vim)"

# ── 1. yazi: Enter on a yaml, a toml, an .xml ────────────────────────────────
# yazi's own rules send text/* to $EDITOR and stop there. A .yaml is
# application/yaml, a .toml application/toml — neither is text/*, so both fall
# through to the catch-all and out to xdg-open.
yazi_toml="$HOME/.config/yazi/yazi.toml"
TEXT_MIMES='application/{yaml,x-yaml,toml,xml,sql,x-shellscript,x-desktop,x-subrip,x-perl,x-python,x-ruby,x-php}'
text_rule=$'\t{ mime = "'"$TEXT_MIMES"$'", use = "edit" },'

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

if [[ -f "$yazi_toml" ]] && grep -qF "$TEXT_MIMES" "$yazi_toml"; then
    skip "yazi.toml already routes text-ish files to \$EDITOR."
elif [[ -f "$yazi_toml" ]] && grep -q '^prepend_rules = \[' "$yazi_toml"; then
    step "Routing yaml/toml/xml to yazi's edit opener"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would add:%s { mime = "%s", use = "edit" } → %s\n' \
            "$C_DIM" "$C_OFF" "$TEXT_MIMES" "${yazi_toml/#$HOME/\~}"
    else
        insert_after '^prepend_rules = \[' "$text_rule"
    fi
    ok "yazi.toml → Enter on a yaml opens vim, not the PDF reader."
elif [[ -f "$yazi_toml" ]] && grep -q '^\[open\]' "$yazi_toml"; then
    # An [open] block written some other way. A second one is a duplicate table,
    # and yazi throws out the WHOLE config over one.
    skip "yazi.toml has an [open] block this repo did not write — text rule left to you."
    skip "Add to its rules:  { mime = \"$TEXT_MIMES\", use = \"edit\" }"
else
    step "Routing yaml/toml/xml to yazi's edit opener"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would append:%s [open] prepend_rules (text → edit) → %s\n' \
            "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        [[ -s "$yazi_toml" ]] && printf '\n' >> "$yazi_toml"
        printf '[open]\nprepend_rules = [\n%s\n]\n' "$text_rule" >> "$yazi_toml"
    fi
    ok "yazi.toml → Enter on a yaml opens vim, not the PDF reader."
fi

# Config errors are silent until launch, so parse-check what we just touched.
yazi_bin="$HOME/.local/bin/yazi"
has_cmd yazi && yazi_bin="yazi"
if [[ "$DRY_RUN" != true ]] && command -v "$yazi_bin" >/dev/null 2>&1; then
    if ! "$yazi_bin" --version </dev/null >/dev/null 2>&1; then
        warn "yazi rejects its config — it will start with preset settings. Details:"
        "$yazi_bin" --version </dev/null 2>&1 | sed 's/^/    /' || true
    fi
fi

# ── 2. Everything else that opens a text file ────────────────────────────────
# Installing Okular is what breaks this: okularApplication_txt.desktop claims
# text/plain, and every text type without a default of its own inherits it.
if is_server; then
    skip "Server profile — no xdg-open defaults to set."
    ok "Text editor default ready — vim in yazi."
    exit 0
fi

if ! has_cmd xdg-mime; then
    warn "xdg-mime not found (xdg-utils) — system text default left as it is."
    exit 0
elif ! has_cmd vim; then
    warn "vim not installed — system text default left as it is."
    exit 0
fi

# Ubuntu's own vim.desktop is Terminal=true, and xdg-open ignores that key: it
# runs Exec as-is, so vim lands on whatever stdout it was handed. Hence our own.
if has_cmd alacritty; then
    TERM_RUN="alacritty -e"
    TERM_BIN="alacritty"
elif has_cmd x-terminal-emulator; then
    TERM_RUN="x-terminal-emulator -e"
    TERM_BIN="x-terminal-emulator"
else
    warn "No terminal emulator found — system text default left as it is."
    exit 0
fi

TEXT_TYPES=(
    text/plain text/markdown
    application/yaml application/x-yaml text/x-yaml
    application/toml application/sql application/x-shellscript
)
DESKTOP_ID="ble-vim.desktop"
DESKTOP_FILE="$HOME/.local/share/applications/$DESKTOP_ID"

# NoDisplay so it stays out of the app menu: Ubuntu's Vim entry is already there,
# and this one exists only to be the mime default.
write_gen "$DESKTOP_FILE" <<EOF
[Desktop Entry]
# Written by best-linux-environment — basic/76-text-editor.sh.
# Do NOT edit: every run rewrites it.
Type=Application
Name=Vim (terminal)
GenericName=Text Editor
Comment=Edit text files in vim, in a terminal window
Exec=$TERM_RUN vim %F
TryExec=$TERM_BIN
Terminal=false
NoDisplay=true
Icon=vim
Categories=Utility;TextEditor;
MimeType=$(IFS=';'; echo "${TEXT_TYPES[*]};")
EOF

if [[ "$GEN_CHANGED" == true && "$DRY_RUN" != true ]] && has_cmd update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# Asked per type: xdg-mime answers one query at a time, and a partial state is
# the normal one — a browser can hold text/markdown while Okular holds the rest.
WRONG=()
for m in "${TEXT_TYPES[@]}"; do
    [[ "$(xdg-mime query default "$m" 2>/dev/null)" == "$DESKTOP_ID" ]] || WRONG+=("$m")
done

if [[ ${#WRONG[@]} -eq 0 ]]; then
    skip "vim is already the system default for every text type."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would set:%s %s as default for %d type(s) — %s\n' \
        "$C_DIM" "$C_OFF" "$DESKTOP_ID" "${#WRONG[@]}" "${WRONG[*]}"
else
    step "Making vim the default for ${#WRONG[@]} text type(s)"
    # One call, not one per type: each is a rewrite of ~/.config/mimeapps.list.
    if xdg-mime default "$DESKTOP_ID" "${WRONG[@]}" 2>/dev/null; then
        ok "xdg-open now opens text files in vim."
    else
        warn "xdg-mime refused — ~/.config/mimeapps.list left as it is."
    fi
fi

ok "Text editor default ready — vim."
