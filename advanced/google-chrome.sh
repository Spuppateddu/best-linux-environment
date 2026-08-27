#!/usr/bin/env bash
# Google Chrome, set up so a coding agent can drive it HEADLESS: the browser,
# the AppArmor profile its sandbox needs, and b-chrome. Firefox stays default.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed google-chrome-stable; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

SRC="$BLE_ROOT/chrome-headless"
CHROME_BIN=/opt/google/chrome/chrome

title "Google Chrome (headless, for coding agents)"

# Like docker.sh, no early exit when the browser is there: the profile and
# b-chrome are the parts that go stale, and a re-run has to repair them.

# ── 1. the browser ───────────────────────────────────────────────────────────
arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if is_installed; then
    skip "google-chrome-stable already installed."
elif [[ "$arch" != amd64 ]]; then
    warn "Google publishes no Linux $arch build of Chrome — nothing to install."
    warn "Use Chromium instead ('sudo apt install chromium-browser'); b-chrome below finds it."
else
    apt_ensure curl gnupg

    # deb822, at the path Chrome's own postinst manages on 26.04: it rewrites
    # this same file, so one source survives instead of a duplicate apt warns about.
    keyring=/usr/share/keyrings/google-chrome.gpg
    sources=/etc/apt/sources.list.d/google-chrome.sources
    legacy=/etc/apt/sources.list.d/google-chrome.list

    if [[ -f "$keyring" && ( -f "$sources" || -f "$legacy" ) ]]; then
        skip "Google's apt repo already configured."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would add key:%s linux_signing_key.pub → %s\n' "$C_DIM" "$C_OFF" "$keyring"
        printf '%s  would write:%s %s\n' "$C_DIM" "$C_OFF" "$sources"
    elif ! can_sudo; then
        warn "sudo unavailable — Google's apt repo not added; run ./setup.sh from a terminal."
    else
        step "Adding Google's apt repo"
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
            | sudo gpg --dearmor --yes -o "$keyring"
        sudo tee "$sources" >/dev/null <<SOURCES
X-Repolib-Name: Google Chrome
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: $keyring
SOURCES
        ok "Google's apt repo added."
    fi

    # Chrome's deb registers itself as an x-www-browser alternative, which can
    # move the default browser off Firefox. Put back whatever was set before.
    before=""
    has_cmd xdg-settings && before="$(xdg-settings get default-web-browser 2>/dev/null || true)"

    apt_ensure google-chrome-stable

    # A Chrome deb old enough to write its own .list instead of rewriting the
    # file above leaves two sources for one repo — apt says so at every update.
    if [[ "$DRY_RUN" != true && -f "$sources" && -f "$legacy" ]] && can_sudo; then
        sudo rm -f "$sources" \
            && ok "Dropped our copy of the apt source — Chrome maintains its own."
    fi

    if [[ -n "$before" && "$DRY_RUN" != true ]]; then
        after="$(xdg-settings get default-web-browser 2>/dev/null || true)"
        if [[ -n "$after" && "$after" != "$before" ]]; then
            xdg-settings set default-web-browser "$before" 2>/dev/null \
                && ok "Default browser kept as $before (Chrome had taken it)." \
                || warn "Chrome became the default browser — set it back with: xdg-settings set default-web-browser $before"
        fi
    fi
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
# Written by best-linux-environment (advanced/google-chrome.sh), and the same
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

ok "Google Chrome ready — headless, sandboxed, and reachable as 'b-chrome'."
ok "Try: b-chrome doctor · b-chrome shot https://example.com /tmp/x.png · b-chrome help"
