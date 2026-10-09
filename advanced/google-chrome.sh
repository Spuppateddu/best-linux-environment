#!/usr/bin/env bash
# Google Chrome, the browser only, from Google's apt repo. Firefox stays default.
# The headless parts for coding agents are advanced/chrome-headless.sh.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed google-chrome-stable; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

if [[ "${1:-}" == --uninstall ]]; then
    title "Google Chrome — uninstall"
    apt_remove google-chrome-stable
    remove_files --sudo /etc/apt/sources.list.d/google-chrome.sources \
        /etc/apt/sources.list.d/google-chrome.list /usr/share/keyrings/google-chrome.gpg
    # b-chrome and the AppArmor profile are useless without the browser: go with it.
    if [[ -x "$HOME/.local/bin/b-chrome" ]]; then
        bash "$BLE_ROOT/advanced/chrome-headless.sh" --uninstall
    fi
    ok "Google Chrome removed. Your profile and the ~/.chrome config repo are kept."
    exit 0
fi

title "Google Chrome"

arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if is_installed; then
    skip "google-chrome-stable already installed."
elif [[ "$arch" != amd64 ]]; then
    warn "Google publishes no Linux $arch build of Chrome — nothing to install."
    warn "Use Chromium instead ('sudo apt install chromium-browser'); b-chrome finds it too."
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

ok "Google Chrome ready. For coding agents, tick 'chrome-headless' too."
