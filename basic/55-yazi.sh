#!/usr/bin/env bash
# Yazi — fast TUI file manager with image/video/PDF preview inside Alacritty.
# Not in apt: yazi ships as a prebuilt binary (→ ~/.local/bin), and preview in a
# graphics-less terminal (Alacritty, even under tmux) needs ueberzugpp, whose only
# Ubuntu build lives in the maintainer's OBS repo — installed here as a .deb.
# yazi auto-detects ueberzugpp at runtime, so no yazi.toml is required.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Yazi"

# ── 1. Preview backends ───────────────────────────────────────────────────────
# ffmpegthumbnailer → video thumbs, poppler-utils → PDF, unar → archives.
# git: ya pkg add (flavor install) clones from GitHub.
apt_ensure ffmpegthumbnailer poppler-utils unar curl unzip git

# ── 2. ueberzugpp — image overlay for terminals without a graphics protocol ───
if has_cmd ueberzugpp; then
    skip "ueberzugpp already installed."
else
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    release="$(lsb_release -rs 2>/dev/null || echo '')"
    base="https://download.opensuse.org/repositories/home:/justkidding/xUbuntu_${release}"
    # Resolve the current .deb filename from the repo index (version-proof).
    deb_path="$(curl -fsSL "$base/Packages" 2>/dev/null \
        | awk -v a="$arch" '$1=="Filename:" && $2 ~ ("^" a "/") {print $2; exit}')"
    if [[ -z "$release" || -z "$deb_path" ]]; then
        warn "No ueberzugpp build for xUbuntu_${release:-?}/${arch} — image preview disabled."
        warn "Grab it manually from https://github.com/jstkdng/ueberzugpp/releases."
    else
        tmp="/tmp/ueberzugpp.$$.deb"
        step "Installing ueberzugpp ($arch) from OBS"
        run curl -fL --progress-bar -o "$tmp" "$base/$deb_path"
        # apt (not dpkg) so the opencv/vips/chafa deps resolve automatically.
        run sudo apt-get install -y "$tmp"
        run rm -f "$tmp"
        ok "ueberzugpp installed."
    fi
fi

# ── 3. Yazi binary — prebuilt release → ~/.local/bin ─────────────────────────
if [[ -x "$HOME/.local/bin/yazi" ]] || has_cmd yazi; then
    skip "yazi already installed."
else
    case "$(uname -m)" in
        x86_64)        ytarget="x86_64-unknown-linux-gnu" ;;
        aarch64|arm64) ytarget="aarch64-unknown-linux-gnu" ;;
        *) fail "Unsupported arch $(uname -m) for the yazi prebuilt binary."; exit 1 ;;
    esac
    url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${ytarget}.zip"
    tmp="/tmp/yazi.$$.zip"; ext="/tmp/yazi.$$.d"
    step "Installing yazi ($ytarget)"
    run mkdir -p "$HOME/.local/bin" "$ext"
    run curl -fL --progress-bar -o "$tmp" "$url"
    run unzip -oq "$tmp" -d "$ext"
    # The zip nests both binaries under yazi-<target>/.
    run install -m755 "$ext/yazi-${ytarget}/yazi" "$HOME/.local/bin/yazi"
    run install -m755 "$ext/yazi-${ytarget}/ya"   "$HOME/.local/bin/ya"
    run rm -rf "$tmp" "$ext"
    ok "yazi installed → ~/.local/bin (open with: yazi)."
fi

# ── 4. Gruvbox flavor — installed via ya, wired in theme.toml ─────────────────
# A "flavor" is a prebuilt theme package; theme.toml just references it by name.
ya="$HOME/.local/bin/ya"
has_cmd ya && ya="ya"
flavor_dir="$HOME/.config/yazi/flavors/gruvbox-dark.yazi"
if [[ -d "$flavor_dir" ]]; then
    skip "gruvbox-dark flavor already installed."
else
    step "Installing gruvbox-dark flavor (ya pkg add)"
    run "$ya" pkg add bennyyip/gruvbox-dark
    ok "gruvbox-dark flavor installed."
fi

theme="$HOME/.config/yazi/theme.toml"
if [[ -f "$theme" ]]; then
    skip "yazi theme.toml exists — leaving flavor untouched."
else
    step "Setting yazi dark flavor to gruvbox-dark"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [flavor] dark=gruvbox-dark → %s\n' "$C_DIM" "$C_OFF" "$theme"
    else
        mkdir -p "$(dirname "$theme")"
        printf '[flavor]\ndark = "gruvbox-dark"\n' > "$theme"
    fi
    ok "yazi theme → gruvbox-dark."
fi

ok "Yazi ready."
