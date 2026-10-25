#!/usr/bin/env bash
# LibreOffice Calc — installs it and makes it what xdg-open hands a spreadsheet
# to: csv, tsv, xlsx, xls, ods. yazi's Enter on a .csv stays vim (text/*).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

apt_app_module libreoffice-calc "LibreOffice Calc" --desktop

# ── Everything that opens a spreadsheet ──────────────────────────────────────
# A .csv is text/csv, which inherits text/plain's default (vim, from
# 76-text-editor) unless it has its own — so a downloaded csv opened in vim.
CALC_DESKTOP="libreoffice-calc.desktop"
CALC_MIMES=(
    text/csv text/tab-separated-values
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    application/vnd.oasis.opendocument.spreadsheet
)

if ! has_cmd xdg-mime; then
    warn "xdg-mime not found (xdg-utils) — system spreadsheet default left as it is."
    exit 0
elif [[ "$DRY_RUN" != true && ! -f "/usr/share/applications/$CALC_DESKTOP" ]]; then
    warn "$CALC_DESKTOP is not installed — system spreadsheet default left as it is."
    exit 0
fi

# Asked per type: xdg-mime answers one query at a time.
WRONG=()
for m in "${CALC_MIMES[@]}"; do
    [[ "$(xdg-mime query default "$m" 2>/dev/null)" == "$CALC_DESKTOP" ]] || WRONG+=("$m")
done

if [[ ${#WRONG[@]} -eq 0 ]]; then
    skip "LibreOffice Calc is already the system default for every spreadsheet type."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would set:%s %s as default for %d type(s) — %s\n' \
        "$C_DIM" "$C_OFF" "$CALC_DESKTOP" "${#WRONG[@]}" "${WRONG[*]}"
else
    step "Making LibreOffice Calc the default for ${#WRONG[@]} spreadsheet type(s)"
    # One call, not one per type: each is a rewrite of ~/.config/mimeapps.list.
    if xdg-mime default "$CALC_DESKTOP" "${WRONG[@]}" 2>/dev/null; then
        ok "xdg-open now opens spreadsheets in LibreOffice Calc."
    else
        warn "xdg-mime refused — ~/.config/mimeapps.list left as it is."
    fi
fi

ok "Spreadsheets ready — LibreOffice Calc."
