#!/usr/bin/env bash
# Drives a whole run — failures, self-update, the @reboot cron, the boot log, the
# summary. Source after lib/common.sh. What one module needs is in common.sh.

[[ -n "${_BLE_RUNNER_LOADED:-}" ]] && return 0
_BLE_RUNNER_LOADED=1

# The script the user actually invoked. self_update re-execs this after a pull,
# so it must be the real path, not $0 as seen from inside a function.
BLE_ENTRY="${BLE_ENTRY:-$BLE_ROOT/setup.sh}"

# Modules that exited non-zero, reported together by finish() so one broken module
# never stops the others. The run still exits non-zero, so `&& …` stays honest.
FAILED=()

# ── self-update ──────────────────────────────────────────────────────────────
# self_update ARG...  — pull, then re-exec the NEW entry script once if it changed.
self_update() {
    local before after
    before="$(git -C "$BLE_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    step "Updating best-linux-environment itself"
    run git -C "$BLE_ROOT" pull --ff-only --quiet \
        || warn "Could not pull $BLE_ROOT — continuing with the current version."
    after="$(git -C "$BLE_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ "$before" != "$after" && "${BLE_SELF_UPDATED:-}" != 1 ]]; then
        ok "Repo updated — re-running the new $(basename "$BLE_ENTRY")."
        BLE_SELF_UPDATED=1 exec bash "$BLE_ENTRY" "$@"
    fi
}

# ── boot log ─────────────────────────────────────────────────────────────────
# Trimmed IN PLACE, never by `mv`: the cron's `>>` holds this file open already.
BLE_LOG_MAX_BYTES="${BLE_LOG_MAX_BYTES:-524288}"   # 512 KiB
BLE_LOG="$BLE_STATE_DIR/boot.log"

trim_boot_log() {
    local keep size
    [[ -f "$BLE_LOG" && "$DRY_RUN" != true ]] || return 0
    size="$(wc -c < "$BLE_LOG" 2>/dev/null || echo 0)"
    (( size > BLE_LOG_MAX_BYTES )) || return 0
    keep="$(tmp_file .log)"
    if tail -c "$BLE_LOG_MAX_BYTES" "$BLE_LOG" > "$keep" 2>/dev/null; then
        cat "$keep" > "$BLE_LOG"
    fi
    rm -f "$keep"
}

# ── @reboot cron ─────────────────────────────────────────────────────────────
# Paths quoted (cron uses /bin/sh); the sleep waits for the network before pulling.
cron_entry() {
    printf "@reboot sleep 45 && /usr/bin/env bash '%s' >> '%s' 2>&1" \
        "$BLE_ROOT/boot.sh" "$BLE_LOG"
}

# grep WITHOUT -q, or crontab SIGPIPEs and this reports "no cron" under pipefail.
# Matched on the repo path, so an older entry script on that line still counts.
cron_installed() { crontab -l 2>/dev/null | grep -F "@reboot" | grep -F "$BLE_ROOT/" >/dev/null; }

# True when the crontab has one of ours but it isn't the line we write today.
cron_stale() {
    cron_installed && ! { crontab -l 2>/dev/null | grep -F "$BLE_ROOT/boot.sh" >/dev/null; }
}

install_cron() {
    if ! has_cmd crontab; then
        warn "crontab not found — install cron first: sudo apt install cron"
        return 1
    fi
    if cron_installed && ! cron_stale; then
        skip "Boot cron already installed."
        return 0
    fi
    local entry; entry="$(cron_entry)"
    if [[ "$DRY_RUN" == true ]]; then
        cron_stale && printf '%s  would replace the old cron line%s\n' "$C_DIM" "$C_OFF"
        printf '%s  would add cron:%s %s\n' "$C_DIM" "$C_OFF" "$entry"
        return 0
    fi
    mkdir -p "$BLE_STATE_DIR"

    # Read it explicitly, not `crontab -l || true`: that swallows every failure
    # alike, and one that isn't "no crontab yet" would wipe your other jobs.
    local existing rc=0
    existing="$(crontab -l 2>/dev/null)" || rc=$?
    if (( rc > 1 )); then
        fail "Could not read the current crontab (exit $rc) — refusing to rewrite it."
        return 1
    fi

    # Drop our own @reboot lines and re-add one. awk, not `grep -v`: grep exits 1
    # when it prints nothing, aborting under `set -e` on a crontab of only our line.
    local kept was_stale=false
    cron_stale && was_stale=true
    kept="$(printf '%s\n' "$existing" | awk -v repo="$BLE_ROOT/" '
        /@reboot/ && index($0, repo) { next }
        { print }')"

    { [[ -n "${kept//[[:space:]]/}" ]] && printf '%s\n' "$kept"
      printf '%s\n' "$entry"; } | crontab -
    if [[ "$was_stale" == true ]]; then
        ok "Boot cron updated to run ./boot.sh (log: ${BLE_LOG/#$HOME/\~})."
    else
        ok "Boot cron installed (log: ${BLE_LOG/#$HOME/\~})."
    fi
}

# ── closing summary ──────────────────────────────────────────────────────────
# Both entry scripts end with this. Exits: 0 clean, 1 if anything failed.
finish() {
    echo
    # `if`, not `[[ … ]] && warn …`: as the last command that would make a
    # successful non-dry run exit 1, and read as failed by any `&& …` chain.
    if [[ "$DRY_RUN" == true ]]; then
        warn "This was a --dry-run: nothing was changed."
    fi

    # Modules keep going past a failure, so say plainly what broke and exit
    # non-zero — a run that skipped half its work must not look like a win.
    if [[ ${#FAILED[@]} -gt 0 ]]; then
        fail "Finished, but ${#FAILED[@]} failed: ${FAILED[*]}"
        fail "Re-run $(basename "$BLE_ENTRY") to retry them (everything else is already done)."
        exit 1
    fi

    ok "Done."
    exit 0
}
