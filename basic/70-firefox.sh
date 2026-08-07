#!/usr/bin/env bash
# Firefox from Mozilla's apt repo, never Ubuntu's snap: the snap replaces
# XCURSOR_PATH, so ~/.icons drops out and the cursor theme breaks, unfixably.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Firefox"
require_desktop "Firefox"

# The unpacked application dir is the one unambiguous "this is the deb" marker:
# Ubuntu's transitional package ships only a /usr/bin/firefox shim.
firefox_is_deb() { [[ -x /usr/lib/firefox/firefox ]]; }

# has_profile ROOT  — profiles.ini naming at least one directory that is on disk.
# NOT `[[ -d ~/.mozilla/firefox ]]`: an empty dir there once cost people a browser.
has_profile() {
    local root="$1" rel
    [[ -f "$root/profiles.ini" ]] || return 1
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        # IsRelative=0 records an absolute Path; everything else is under ROOT.
        if [[ "$rel" == /* ]]; then
            [[ -d "$rel" ]] && return 0
        else
            [[ -d "$root/$rel" ]] && return 0
        fi
    done < <(awk -F= '/^[[:space:]]*Path[[:space:]]*=/ {sub(/\r$/, "", $2); print $2}' "$root/profiles.ini")
    return 1
}

# ── 1. Mozilla apt repo ──────────────────────────────────────────────────────
apt_repo_add mozilla \
    "https://packages.mozilla.org/apt/repo-signing-key.gpg" \
    "deb [signed-by=/usr/share/keyrings/mozilla.gpg] https://packages.mozilla.org/apt mozilla main"

# Not optional: the transitional deb's epoch sorts above Mozilla's version, so
# apt would "upgrade" back to the snap. Named packages, never `Package: *`.
PIN_FILE="/etc/apt/preferences.d/mozilla"
PIN_PACKAGES="firefox firefox-l10n-* firefox-esr firefox-esr-l10n-*"
# Test the narrowed line, so an older `Package: *` pin is rewritten. -F is
# load-bearing: as a regex the `*` never matches the literal one in the file.
if [[ -f "$PIN_FILE" ]] && grep -Fqx "Package: $PIN_PACKAGES" "$PIN_FILE"; then
    skip "apt pin for packages.mozilla.org already in place."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would write:%s Pin-Priority 1000 (%s) → %s\n' "$C_DIM" "$C_OFF" "$PIN_PACKAGES" "$PIN_FILE"
elif ! can_sudo; then
    warn "sudo unavailable — could not write $PIN_FILE."
else
    step "Pinning Firefox from packages.mozilla.org above the Ubuntu archive"
    printf 'Package: %s\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' "$PIN_PACKAGES" \
        | sudo tee "$PIN_FILE" >/dev/null
    ok "apt pin written."
fi

# ── 2. Install the deb ───────────────────────────────────────────────────────
# Not apt_ensure: the transitional package is *also* called `firefox`.
if firefox_is_deb; then
    skip "Firefox deb already installed ($(firefox --version 2>/dev/null || echo present))."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would install:%s firefox (from packages.mozilla.org)\n' "$C_DIM" "$C_OFF"
elif ! can_sudo; then
    warn "sudo unavailable (non-interactive) — skipped the Firefox deb install."
    warn "Run ./setup.sh from a terminal to pick it up."
else
    apt_refresh
    step "Installing Firefox from packages.mozilla.org"
    # --allow-downgrades is mandatory: the epoch makes apt read this swap as a
    # downgrade, and `-y` alone hard-refuses one, aborting the module.
    sudo apt-get install -y --allow-downgrades firefox
    firefox_is_deb && ok "Firefox deb installed." \
        || warn "Install ran but /usr/lib/firefox is missing — check apt output above."
fi

# ── 3. Migrate the snap profile ──────────────────────────────────────────────
# Copied, never moved, so the snap's own copy survives as a fallback.
SNAP_MOZ="$HOME/snap/firefox/common/.mozilla"
DEB_MOZ="$HOME/.mozilla"

# Section 4 keys the snap removal off THIS, not off a directory existing —
# see has_profile above for why.
DEB_PROFILE_OK=false
has_profile "$DEB_MOZ/firefox" && DEB_PROFILE_OK=true

if [[ ! -d "$SNAP_MOZ/firefox" ]]; then
    :   # nothing to migrate — fresh machine, or already cleaned up
elif [[ "$DEB_PROFILE_OK" == true ]]; then
    skip "~/.mozilla already holds a profile — leaving the snap profile alone."
elif pgrep -x firefox >/dev/null 2>&1; then
    warn "Firefox is running — not copying a live profile (sqlite corruption risk)."
    warn "Quit Firefox and re-run ./setup.sh to migrate it."
else
    # cp -a merges, so an empty leftover ~/.mozilla/firefox is fine to copy into.
    step "Migrating profile: ~/snap/firefox/common/.mozilla → ~/.mozilla"
    run mkdir -p "$DEB_MOZ"
    run cp -a "$SNAP_MOZ/." "$DEB_MOZ/"
    if [[ "$DRY_RUN" == true ]]; then
        DEB_PROFILE_OK=true
    elif has_profile "$DEB_MOZ/firefox"; then
        DEB_PROFILE_OK=true
        ok "Profile migrated."
    else
        # Section 4 deletes on the strength of this flag, so it is only ever set
        # by re-reading what actually landed on disk.
        warn "Copy finished but ~/.mozilla still names no profile on disk."
        warn "Leaving everything as it is — the snap will not be removed."
    fi
fi

# Copying is not enough: since 67 each install claims a dedicated profile and
# comes up blank. MOZ_LEGACY_PROFILES=1 makes profiles.ini's Default=1 win again.
xsessionrc_export MOZ_LEGACY_PROFILES 1
if [[ "$XSESSIONRC_CHANGED" == true ]]; then
    warn "Takes effect at the next login. If you start Firefox before then and it"
    warn "comes up empty, it made a dedicated profile — repoint it with:"
    warn "  sed -i 's/^Default=.*default-release\$/Default=<your-profile>/' \\"
    warn "    ~/.mozilla/firefox/profiles.ini ~/.mozilla/firefox/installs.ini"
fi

# ── 4. Retire the snap ───────────────────────────────────────────────────────
# Destructive — `snap remove` takes ~/snap/firefox too. DEB_PROFILE_OK is the guard.
if ! has_cmd snap || ! snap list firefox >/dev/null 2>&1; then
    skip "No Firefox snap installed."
elif ! firefox_is_deb; then
    warn "Leaving the Firefox snap in place — the deb isn't installed yet."
elif [[ -d "$SNAP_MOZ/firefox" && "$DEB_PROFILE_OK" != true ]]; then
    warn "Leaving the Firefox snap in place — its profile is not in ~/.mozilla yet."
    warn "Quit Firefox and re-run ./setup.sh to migrate it."
elif ! can_sudo && [[ "$DRY_RUN" != true ]]; then
    warn "sudo unavailable — Firefox snap left installed."
else
    step "Removing the Firefox snap (snapd keeps a 31-day snapshot — see: snap saved)"
    run sudo snap remove firefox || warn "Could not remove the Firefox snap."
    ok "Firefox snap removed."
fi

# Report the wiring rather than doing it, so a run that installed the browser
# but never reached the config repo doesn't look complete (as in 52-alacritty.sh).
repo="$HOME/.firefox"
if [[ -x "$repo/install.sh" ]]; then
    skip "Prefs, add-ons and key bindings belong to ~/.firefox/install.sh (run by 10-tools.sh)."
elif [[ -d "$repo" ]]; then
    warn "~/.firefox has no install.sh — nothing configured. Update it:  bash basic/10-tools.sh firefox"
else
    warn "Config repo ~/.firefox not cloned yet — browser installed, nothing configured."
    warn "Get the config: ./setup.sh  (tick firefox in the core list)"
fi

ok "Firefox ready."
