#!/usr/bin/env bash
# Chrome set up so a coding agent can drive it HEADLESS: the AppArmor profile its
# sandbox needs, b-chrome, and CHROME_PATH. Installs Google Chrome first if missing.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { [[ -x "$HOME/.local/bin/b-chrome" ]]; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

SRC="$BLE_ROOT/chrome-headless"
CHROME_BIN=/opt/google/chrome/chrome

if [[ "${1:-}" == --uninstall ]]; then
    title "Headless Chrome — uninstall (the browser stays)"
    # Only a profile this script wrote: stock 26.04 ships its own in the apparmor package.
    if grep -qs 'Written by best-linux-environment' /etc/apparmor.d/chrome; then
        remove_files --sudo /etc/apparmor.d/chrome
    fi
    remove_files "$HOME/.local/bin/b-chrome"
    # Only the lines section 4 below wrote — they all carry this same comment.
    for shell_name in zsh bash; do
        local_file="$HOME/.$shell_name/$shell_name-alias.local"
        grep -qs 'b-chrome / Puppeteer — delete this line to undo' "$local_file" || continue
        run sed -i '/# b-chrome \/ Puppeteer — delete this line to undo$/d' "$local_file"
        [[ "$DRY_RUN" == true ]] || ok "CHROME_PATH and PUPPETEER_EXECUTABLE_PATH dropped from ${local_file/#$HOME/\~}."
    done
    ok "Headless Chrome removed. Google Chrome itself is kept."
    exit 0
fi

title "Headless Chrome (for coding agents)"

# ── 1. the browser ───────────────────────────────────────────────────────────
# Its own entry; run here too so ticking only this one still gives a working b-chrome.
if apt_installed google-chrome-stable; then
    skip "google-chrome-stable already installed."
else
    bash "$BLE_ROOT/advanced/google-chrome.sh"
fi

# ── 2. the sandbox ───────────────────────────────────────────────────────────
# Chrome's sandbox needs the unprivileged user namespace Ubuntu restricts (on
# since 24.04, still on in 26.04). The sysctl is read, never the release number.

# Stock 26.04 already ships /etc/apparmor.d/chrome in the `apparmor` package, so
# this usually has nothing to do; a container or stripped image gets one here.
restrict="$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)"
if [[ "$restrict" != 1 ]]; then
    skip "Unprivileged user namespaces are not restricted here — the sandbox needs nothing."
elif ! has_cmd apparmor_parser; then
    warn "AppArmor restricts user namespaces but apparmor_parser is missing — leaving it alone."
elif grep -rqs "$CHROME_BIN" /etc/apparmor.d/; then
    skip "An AppArmor profile already names $CHROME_BIN."
elif [[ ! -x "$CHROME_BIN" ]]; then
    skip "No $CHROME_BIN on this machine — no profile to write."
elif ! can_sudo; then
    skip "No terminal to authenticate sudo — the AppArmor profile is left as it is."
else
    step "Writing /etc/apparmor.d/chrome so Chrome may open a user namespace"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s /etc/apparmor.d/chrome, then reload it\n' "$C_DIM" "$C_OFF"
    else
        # Ubuntu's own profile, verbatim in spirit: it confines nothing, it only
        # gives Chrome a name AppArmor can grant `userns` to.
        sudo tee /etc/apparmor.d/chrome >/dev/null <<'PROFILE'
# Written by best-linux-environment (advanced/chrome-headless.sh), and the same
# contents Ubuntu's `apparmor` package ships: a name AppArmor can grant userns to.

abi <abi/4.0>,
include <tunables/global>

profile chrome /opt/google/chrome/chrome flags=(unconfined) {
  userns,
  @{exec_path} mr,

  include if exists <local/chrome>
}
PROFILE
        sudo apparmor_parser -r /etc/apparmor.d/chrome 2>/dev/null \
            && ok "AppArmor profile loaded — the Chrome sandbox can start." \
            || warn "Could not load the profile — b-chrome falls back to --no-sandbox."
    fi
fi

# ── 3. b-chrome ──────────────────────────────────────────────────────────────
# In ~/.local/bin like b-idle: one copy, on PATH for both shells. This is the
# part an agent actually calls.
if [[ ! -r "$SRC/b-chrome" ]]; then
    warn "Missing $SRC/b-chrome — skipping the helper."
elif cmp -s "$SRC/b-chrome" "$HOME/.local/bin/b-chrome"; then
    skip "b-chrome already current."
else
    run mkdir -p "$HOME/.local/bin"
    run install -m 0755 "$SRC/b-chrome" "$HOME/.local/bin/b-chrome"
    ok "b-chrome installed to ~/.local/bin."
fi

# ── 4. the two variables node tooling reads ──────────────────────────────────
# Into <shell>-alias.local, where 15-temps-alias.sh puts b-temp. Never over a
# value you set: a project pinned to its own Chrome build stays pinned.
if [[ -x "$CHROME_BIN" || "$(command -v google-chrome-stable 2>/dev/null)" ]]; then
    chrome_path="$(command -v google-chrome-stable 2>/dev/null || printf '%s' "$CHROME_BIN")"
    for shell_name in zsh bash; do
        alias_file="$HOME/.$shell_name/$shell_name-alias"
        local_file="$alias_file.local"
        [[ -f "$alias_file" ]] || continue
        for var in CHROME_PATH PUPPETEER_EXECUTABLE_PATH; do
            if grep -hEq "^[[:space:]]*export[[:space:]]+$var=" "$alias_file" "$local_file" 2>/dev/null; then
                skip "$shell_name: $var is already set — left as it is."
                continue
            fi
            ensure_line "$local_file" "^[[:space:]]*export[[:space:]]+$var=" \
                "export $var=\"$chrome_path\"   # b-chrome / Puppeteer — delete this line to undo"
        done
    done
fi

ok "Headless Chrome ready — sandboxed, and reachable as 'b-chrome'."
ok "Try: b-chrome doctor · b-chrome shot https://example.com /tmp/x.png · b-chrome help"
