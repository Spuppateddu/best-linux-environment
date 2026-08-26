#!/usr/bin/env bash
# PDF viewer — Okular when installed, Firefox when not, in the two places that
# decide what opens a PDF: yazi's Enter and xdg-open. Installs nothing itself.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "PDF viewer"
require_desktop "PDF viewer"

# ── 1. Which viewer ──────────────────────────────────────────────────────────
# Okular first, always — but it is a `secondary` app, so it may not be here.
# advanced/okular.sh re-runs this module the moment it installs the package.

# `--` stops "-file.pdf" being read as an option: Okular's Qt parser takes it,
# Firefox would open "--" as a URL instead, so the fallback goes without.

# %s, not "$@": yazi hands `run` to a shell with NO positional arguments, so
# "$@" expands to nothing and the viewer opens empty. %s is every selected file.
if has_cmd okular; then
    PDF_RUN='okular -- %s'
    PDF_DESC="Okular"
    PDF_DESKTOP="okularApplication_pdf.desktop"
    # x-gzpdf/x-bzpdf are a gzipped and a bzipped PDF: Okular reads both,
    # Firefox neither, so they only join the list on this branch.
    PDF_MIMES=(application/pdf application/x-gzpdf application/x-bzpdf)
elif has_cmd firefox; then
    PDF_RUN='firefox %s'
    PDF_DESC="Firefox (PDF)"
    PDF_DESKTOP="firefox.desktop"
    PDF_MIMES=(application/pdf)
    skip "Okular is not installed — falling back to Firefox for PDFs."
    skip "Tick 'okular' in ./setup.sh's secondary list to make Okular the default."
else
    warn "Neither okular nor firefox is installed — PDF defaults left as they are."
    exit 0
fi

step "PDF viewer → $PDF_DESC"

# ── 2. yazi: Enter on a PDF ──────────────────────────────────────────────────
# 57-image-viewer.sh owns [opener] image, this one owns [opener] pdf. They share
# the [open] array — TOML takes no second [open] — so we insert into it.
yazi_toml="$HOME/.config/yazi/yazi.toml"
pdf_line=$'\t{ run = \''"$PDF_RUN"$'\', orphan = true, desc = "'"$PDF_DESC"$'", for = "unix" },'
pdf_key=$'pdf = [\n'"$pdf_line"$'\n]'
open_rule=$'\t{ mime = "application/pdf", use = "pdf" },'

# Not "Firefox" or "nsxiv": 57 rewrites any line carrying one of those onto its
# own image opener. It matches the closing quote, so "Firefox (PDF)" is invisible.
OURS='desc = "(Okular|Firefox \(PDF\))"'

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
    step "Wiring the PDF opener into yazi.toml"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [opener] pdf + [open] rule → %s\n' \
            "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        printf '[opener]\n%s\n\n[open]\nprepend_rules = [\n%s\n]\n' "$pdf_key" "$open_rule" > "$yazi_toml"
    fi
    ok "yazi.toml → Enter on a PDF opens $PDF_DESC."
else
    # ── 2a. the [opener] pdf key ──────────────────────────────────────────────
    if grep -qF "$PDF_RUN" "$yazi_toml"; then
        skip "yazi.toml already opens PDFs in $PDF_DESC."
    elif grep -Eq "$OURS" "$yazi_toml"; then
        # Ours to rewrite: the viewer changed under us — Okular installed, or removed.
        step "Pointing yazi's PDF opener at $PDF_DESC"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would rewrite:%s [opener] pdf → %s → %s\n' \
                "$C_DIM" "$C_OFF" "$PDF_RUN" "${yazi_toml/#$HOME/\~}"
        else
            tmp="$(tmp_file .toml)"
            awk -v new="$pdf_line" \
                '/desc = "Okular"/ || /desc = "Firefox \(PDF\)"/ { print new; next } { print }' \
                "$yazi_toml" > "$tmp"
            cat "$tmp" > "$yazi_toml"
            rm -f "$tmp"
        fi
        ok "yazi.toml → Enter on a PDF opens $PDF_DESC."
    elif grep -Eq '^[[:space:]]*pdf[[:space:]]*=' "$yazi_toml"; then
        # Hand-written. A second pdf key is a duplicate, and yazi throws out the
        # WHOLE config over one — more than the key you already set is worth.
        skip "yazi.toml has a pdf opener this repo did not write — left to you."
        skip "Point it at:  $PDF_RUN"
    elif grep -q '^\[opener\]' "$yazi_toml"; then
        step "Adding the PDF opener to yazi.toml"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would add:%s [opener] pdf → %s → %s\n' \
                "$C_DIM" "$C_OFF" "$PDF_RUN" "${yazi_toml/#$HOME/\~}"
        else
            insert_after '^\[opener\]' "$pdf_key"
        fi
        ok "yazi.toml → Enter on a PDF opens $PDF_DESC."
    else
        step "Wiring the PDF opener into yazi.toml"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would append:%s [opener] pdf → %s\n' "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
        else
            [[ -s "$yazi_toml" ]] && printf '\n' >> "$yazi_toml"
            printf '[opener]\n%s\n' "$pdf_key" >> "$yazi_toml"
        fi
        ok "yazi.toml → Enter on a PDF opens $PDF_DESC."
    fi

    # ── 2b. the [open] rule pointing application/pdf at that key ──────────────
    if grep -q 'mime = "application/pdf"' "$yazi_toml"; then
        skip "yazi.toml already routes application/pdf to the pdf opener."
    elif grep -q '^prepend_rules = \[' "$yazi_toml"; then
        step "Routing application/pdf to the pdf opener"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would add:%s { mime = "application/pdf", use = "pdf" } → %s\n' \
                "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
        else
            insert_after '^prepend_rules = \[' "$open_rule"
        fi
        ok "yazi.toml → application/pdf uses the pdf opener."
    elif grep -q '^\[open\]' "$yazi_toml"; then
        # An [open] block written some other way. A second one is a duplicate
        # table, so this stops rather than breaking the whole config.
        skip "yazi.toml has an [open] block this repo did not write — pdf rule left to you."
        skip 'Add to its rules:  { mime = "application/pdf", use = "pdf" }'
    else
        step "Routing application/pdf to the pdf opener"
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would append:%s [open] prepend_rules (application/pdf) → %s\n' \
                "$C_DIM" "$C_OFF" "${yazi_toml/#$HOME/\~}"
        else
            printf '\n[open]\nprepend_rules = [\n%s\n]\n' "$open_rule" >> "$yazi_toml"
        fi
        ok "yazi.toml → application/pdf uses the pdf opener."
    fi
fi

# ── 3. Everything else that opens a PDF ──────────────────────────────────────
# xdg-open's default — a download, a mail attachment. Ubuntu leaves it on
# whichever browser registered last, so a downloaded PDF opens in a tab.
if ! has_cmd xdg-mime; then
    warn "xdg-mime not found (xdg-utils) — system PDF default left as it is."
elif [[ ! -f "/usr/share/applications/$PDF_DESKTOP" ]]; then
    warn "$PDF_DESKTOP is not installed — system PDF default left as it is."
else
    # Asked per type: xdg-mime answers one query at a time, and a partial
    # state is the normal one — the browser can hold application/pdf alone.
    WRONG=()
    for m in "${PDF_MIMES[@]}"; do
        [[ "$(xdg-mime query default "$m" 2>/dev/null)" == "$PDF_DESKTOP" ]] || WRONG+=("$m")
    done

    if [[ ${#WRONG[@]} -eq 0 ]]; then
        skip "$PDF_DESC is already the system default for every PDF type."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would set:%s %s as default for %d type(s) — %s\n' \
            "$C_DIM" "$C_OFF" "$PDF_DESKTOP" "${#WRONG[@]}" "${WRONG[*]}"
    else
        step "Making $PDF_DESC the default for ${#WRONG[@]} PDF type(s)"
        # One call, not one per type: each is a rewrite of ~/.config/mimeapps.list.
        if xdg-mime default "$PDF_DESKTOP" "${WRONG[@]}" 2>/dev/null; then
            ok "xdg-open now opens PDFs in $PDF_DESC."
        else
            warn "xdg-mime refused — ~/.config/mimeapps.list left as it is."
        fi
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

ok "PDF viewer ready — $PDF_DESC."
