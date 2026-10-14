#!/usr/bin/env bash
# glow — markdown in the terminal, plus 'mdv' (glow centered and full screen) and
# the styles both read: glow's own dark and light, and a gruvbox one, the default.
# apt owns the binary; this module owns the files in glow/.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/glow"
STYLES="$HOME/.config/glow/styles"
CONF="$HOME/.config/glow/glow.yml"

title "glow + mdv"

# Normally done by modules.conf's apt: action already; here so the module also
# works when run on its own.
has_cmd glow || apt_ensure glow

# install_file MODE SRC DEST  — copy only when the contents differ, so ./boot.sh
# re-running this at every boot says nothing.
install_file() {
    if cmp -s "$2" "$3"; then
        skip "${3/#"$HOME"/\~} already current."
    else
        run install -D -m "$1" "$2" "$3"
        ok "${3/#"$HOME"/\~} installed."
    fi
}

install_file 0755 "$SRC/mdv" "$HOME/.local/bin/mdv"
for f in "$SRC"/styles/*.json; do
    install_file 0644 "$f" "$STYLES/$(basename "$f")"
done

# Plain `glow` gets gruvbox too. glow does not expand ~ in this file, hence the
# full path. Rewritten by ./setup.sh, never by ./boot.sh: edits made between two
# setups survive the boots in between.
want_conf=$(cat <<YAML
# Written by best-linux-environment (basic/45-glow.sh). ./setup.sh rewrites it.
# style name or JSON path
style: "$STYLES/gruvbox.json"
# mouse support (TUI-mode only)
mouse: false
# use pager to display markdown
pager: false
# word-wrap at width (0 = glow picks: the terminal, up to 120)
width: 0
# show all files, including hidden and ignored.
all: false
YAML
)
if [[ -f "$CONF" ]] && [[ "$(cat "$CONF")" == "$want_conf" ]]; then
    skip "~/.config/glow/glow.yml already uses gruvbox."
elif [[ -f "$CONF" ]] && ! force_config; then
    skip "~/.config/glow/glow.yml left as it is — ./setup.sh rewrites it."
else
    run mkdir -p "$(dirname "$CONF")"
    if [[ "$DRY_RUN" == true ]]; then
        skip "would write ~/.config/glow/glow.yml (style: gruvbox)"
    else
        printf '%s\n' "$want_conf" > "$CONF"
        ok "~/.config/glow/glow.yml → gruvbox."
    fi
fi

ok "glow ready — 'mdv file.md' opens a markdown file centered and full screen."
