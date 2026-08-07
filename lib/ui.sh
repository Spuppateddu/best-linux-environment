#!/usr/bin/env bash
# The two list widgets — checklist (any number) and radiolist (exactly one). Source
# after lib/common.sh. With no terminal both print the list and keep the defaults.

[[ -n "${_BLE_UI_LOADED:-}" ]] && return 0
_BLE_UI_LOADED=1

# ── one keypress → one word ──────────────────────────────────────────────────
# Arrows are three bytes (ESC [ A); the tail is read with a timeout so ESC alone works.
_ble_read_key() {
    local k rest=''
    IFS= read -rsn1 k 2>/dev/null || { printf 'enter'; return; }
    case "$k" in
        $'\e')
            # 0.3s, not 50ms: over ssh the two bytes after ESC lag, and a short
            # timeout turns an arrow key into an Escape. The wide window costs nothing.
            read -rsn2 -t 0.3 rest 2>/dev/null || rest=''
            case "$rest" in
                '[A') printf 'up' ;;
                '[B') printf 'down' ;;
                *)    printf 'esc' ;;
            esac
            ;;
        '')  printf 'enter' ;;
        ' ') printf 'space' ;;
        *)   printf '%s' "$k" ;;
    esac
}

# Cut a string to N display columns. ${#s} counts characters, close enough for
# labels that are ASCII plus a few dashes and arrows.
_ble_fit() {
    local s="$1" max="$2"
    (( max < 10 )) && max=10
    if (( ${#s} > max )); then printf '%s…' "${s:0:max-1}"; else printf '%s' "$s"; fi
}

# _ble_fit_row WIDTH LABEL NOTE  — fit label and note TOGETHER on one line, or the
# redraw smears. Label wins ties; the note is capped at a third and dropped first.
_ble_fit_row() {
    local width="$1" label="$2" note="$3"
    # The prefix before the label is 7 columns, plus one spare: a row filling the
    # terminal exactly has already wrapped by the time the newline is written.
    local avail=$(( width - 8 ))
    (( avail < 20 )) && avail=20
    local gap=3 note_cols=0 note_max
    if [[ -n "$note" ]]; then
        # A third of the row, never enough to push the label under 24 columns.
        # Below 10 the note is dropped — _ble_fit's own floor is 10 anyway.
        note_max=$(( avail / 3 ))
        (( note_max > avail - 24 - gap )) && note_max=$(( avail - 24 - gap ))
        if (( note_max < 10 )); then
            note=''
        else
            note="$(_ble_fit "$note" "$note_max")"
            note_cols=$(( ${#note} + gap ))
        fi
    fi
    _BLE_ROW_LABEL="$(_ble_fit "$label" $(( avail - note_cols )))"
    _BLE_ROW_NOTE="$note"
}

# checklist HEADING [HINT]  — edits CHK_STATE in place.
checklist() {
    local heading="$1" hint="${2:-}"
    local n=${#CHK_LABELS[@]}
    (( n )) || return 0

    # Width is read once per call: a terminal resized mid-list is rare enough
    # not to be worth re-measuring every frame.
    local width; width="$(tput cols 2>/dev/null || echo 80)"
    (( width > 20 )) || width=80

    printf '\n%s══ %s ══%s\n' "$C_BOLD" "$heading" "$C_OFF"
    [[ -n "$hint" ]] && printf '%s   %s%s\n' "$C_DIM" "$hint" "$C_OFF"

    local i
    # No terminal → show the list, change nothing. The boot cron and `| tee`
    # hit this, and taking the defaults is the only honest answer.
    if [[ ! -t 0 || ! -t 1 ]]; then
        skip "No terminal to ask on — keeping the defaults below."
        for i in "${!CHK_LABELS[@]}"; do
            printf '   %s %s\n' \
                "$( ((CHK_STATE[i])) && printf '[x]' || printf '[ ]' )" "${CHK_LABELS[$i]}"
        done
        return 0
    fi

    printf '%s   ↑/↓ move · space toggle · a all · n none · enter confirm%s\n\n' \
        "$C_DIM" "$C_OFF"

    local cur=0 first=1 key
    # The cursor is hidden here and put back on every exit path, Ctrl-C included,
    # or the shell this returns to is left with an invisible cursor.
    printf '\033[?25l'
    trap 'printf "\033[?25h"; exit 130' INT

    while :; do
        if (( first )); then first=0; else printf '\033[%dA' "$n"; fi
        for i in "${!CHK_LABELS[@]}"; do
            local mark box row note=''
            # Label and note are fitted TOGETHER so the row cannot wrap — fitting
            # only the label smears the list down the screen. See _ble_fit_row.
            _ble_fit_row "$width" "${CHK_LABELS[$i]}" "${CHK_NOTE[$i]:-}"
            row="$_BLE_ROW_LABEL"
            [[ -n "$_BLE_ROW_NOTE" ]] && note="   ${C_DIM}${_BLE_ROW_NOTE}${C_OFF}"
            if (( i == cur )); then mark="${C_BLUE}❯${C_OFF}"; else mark=' '; fi
            if (( CHK_STATE[i] )); then
                box="${C_GREEN}[x]${C_OFF}"
            else
                box="${C_DIM}[ ]${C_OFF}"
            fi
            (( i == cur )) && row="${C_BOLD}${row}${C_OFF}"
            # \033[2K clears the whole line first: without it a short row drawn
            # over a longer one leaves the tail of the old text behind.
            printf '\033[2K %s %s %s%s\n' "$mark" "$box" "$row" "$note"
        done

        key="$(_ble_read_key)"
        # `x=$(( … ))` throughout, never `(( x = … ))`: under `set -e` an arithmetic
        # command evaluating to zero exits non-zero and would kill the script.
        case "$key" in
            up|k)      cur=$(( (cur - 1 + n) % n )) ;;
            down|j)    cur=$(( (cur + 1) % n )) ;;
            space|x)   CHK_STATE[cur]=$(( 1 - CHK_STATE[cur] )) ;;
            a|A)       for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=1; done ;;
            n|N)       for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=0; done ;;
            enter)     break ;;
            # q leaves the list as it stands; Escape does NOT, because a laggy
            # arrow key arrives as a bare ESC and must not end the list.
            q|Q)       break ;;
            esc)       ;;
        esac
    done

    printf '\033[?25h'
    trap - INT
    return 0
}

# radiolist HEADING [HINT]  — the same widget and the same CHK_* arrays, one answer
# only: the dot follows the cursor, and the first ticked row going in is the default.
radiolist() {
    local heading="$1" hint="${2:-}"
    local n=${#CHK_LABELS[@]}
    (( n )) || return 0

    local width; width="$(tput cols 2>/dev/null || echo 80)"
    (( width > 20 )) || width=80

    printf '\n%s══ %s ══%s\n' "$C_BOLD" "$heading" "$C_OFF"
    [[ -n "$hint" ]] && printf '%s   %s%s\n' "$C_DIM" "$hint" "$C_OFF"

    # Open on the default, and make sure there IS one: a caller that ticked
    # nothing gets row 0 rather than a list with no answer in it.
    local i cur=0
    for i in "${!CHK_STATE[@]}"; do
        if (( CHK_STATE[i] )); then cur=$i; break; fi
    done
    for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=0; done
    CHK_STATE[cur]=1

    # No terminal → print the list and keep the default, exactly as checklist
    # does. The boot cron never reaches here (it asks nothing), but `| tee` does.
    if [[ ! -t 0 || ! -t 1 ]]; then
        skip "No terminal to ask on — keeping the default below."
        for i in "${!CHK_LABELS[@]}"; do
            printf '   %s %s\n' \
                "$( ((CHK_STATE[i])) && printf '(•)' || printf '( )' )" "${CHK_LABELS[$i]}"
        done
        return 0
    fi

    printf '%s   ↑/↓ pick one · enter confirm%s\n\n' "$C_DIM" "$C_OFF"

    local first=1 key
    printf '\033[?25l'
    trap 'printf "\033[?25h"; exit 130' INT

    while :; do
        if (( first )); then first=0; else printf '\033[%dA' "$n"; fi
        for i in "${!CHK_LABELS[@]}"; do
            local mark box row note=''
            # Together, so the row cannot wrap — see _ble_fit_row and checklist.
            _ble_fit_row "$width" "${CHK_LABELS[$i]}" "${CHK_NOTE[$i]:-}"
            row="$_BLE_ROW_LABEL"
            [[ -n "$_BLE_ROW_NOTE" ]] && note="   ${C_DIM}${_BLE_ROW_NOTE}${C_OFF}"
            if (( i == cur )); then mark="${C_BLUE}❯${C_OFF}"; else mark=' '; fi
            # Round brackets, not square: the shape says "one of these".
            if (( CHK_STATE[i] )); then
                box="${C_GREEN}(•)${C_OFF}"
            else
                box="${C_DIM}( )${C_OFF}"
            fi
            (( i == cur )) && row="${C_BOLD}${row}${C_OFF}"
            printf '\033[2K %s %s %s%s\n' "$mark" "$box" "$row" "$note"
        done

        key="$(_ble_read_key)"
        # `x=$(( … ))`, never `(( x = … ))` — see the note in checklist: an
        # arithmetic command evaluating to zero exits non-zero under `set -e`.
        case "$key" in
            up|k)   cur=$(( (cur - 1 + n) % n )) ;;
            down|j) cur=$(( (cur + 1) % n )) ;;
            # space is a no-op that redraws: the dot already followed the cursor.
            # Accepted anyway, because it is the obvious key after the checklists.
            space|x) ;;
            enter|q|Q) break ;;
            # Escape does nothing, for the reason checklist spells out: a laggy
            # arrow key can arrive as a bare ESC, and it must not end the list.
            esc) ;;
        esac
        # The dot follows the cursor every frame, so what you see ticked is what
        # enter gives you — no second key, and no cursor and dot on different rows.
        for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=0; done
        CHK_STATE[cur]=1
    done

    printf '\033[?25h'
    trap - INT
    return 0
}

# chk_reset  — start a fresh list.
chk_reset() { CHK_LABELS=(); CHK_STATE=(); CHK_NOTE=(); }

# chk_add LABEL STATE [NOTE]  — append one row.
chk_add() {
    CHK_LABELS+=("$1")
    CHK_STATE+=("$2")
    CHK_NOTE+=("${3:-}")
}

# chk_count  — how many rows came back ticked.
chk_count() {
    local i c=0
    # `c=$((c+1))` and an `if`, for the `set -e` reason above: `(( c++ ))` returns
    # the value BEFORE the increment, so the first row counted would exit.
    for i in ${CHK_STATE[@]+"${CHK_STATE[@]}"}; do
        if (( i )); then c=$((c + 1)); fi
    done
    printf '%d' "$c"
}

# chk_picked  — print the 0-based index of every ticked row, one per line, so a
# caller can map them back to whatever it built the list from.
chk_picked() {
    local i
    for i in "${!CHK_STATE[@]}"; do
        if (( CHK_STATE[i] )); then printf '%s\n' "$i"; fi
    done
}
