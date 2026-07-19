#!/usr/bin/env bash
# Yazi — fast TUI file manager with image/video/PDF preview inside Alacritty.
# Not in apt: yazi ships as a prebuilt binary (→ ~/.local/bin), and preview in a
# graphics-less terminal (Alacritty, even under tmux) needs ueberzugpp, whose only
# Ubuntu build lives in the maintainer's OBS repo — installed here as a .deb.
# yazi auto-detects ueberzugpp at runtime, so no yazi.toml is required.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Yazi"

# ── 1. Preview backends + navigation ──────────────────────────────────────────
# ffmpegthumbnailer → video thumbs, poppler-utils → PDF, unar/7z → archives.
# zoxide → the z/Z directory-jump bindings. fzf is NOT apt-installed here: apt's
# 0.44 renders the picker blank when yazi pipes its stdout (see section 3b).
# git: ya pkg add (flavor install) clones from GitHub.
# 26.04 dropped p7zip-full in favour of 7zip (same 7z/7zz binaries); fall back
# to the old name on releases that still ship it. Capture the candidate first
# (not `| grep -q`): under pipefail, grep -q closing the pipe would SIGPIPE
# apt-cache and wrongly fail the test.
sevenzip=p7zip-full
sevenzip_cand="$(apt-cache policy 7zip 2>/dev/null | awk '/Candidate:/ {print $2}')"
[[ "$sevenzip_cand" =~ ^[0-9] ]] && sevenzip=7zip
apt_ensure ffmpegthumbnailer poppler-utils unar "$sevenzip" curl unzip git zoxide

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

# ── 3b. fzf — interactive picker for the z/Z bindings ────────────────────────
# yazi pipes fzf's stdout to read the selection; apt's fzf 0.44 mishandles that
# and paints nothing (works standalone, blank inside yazi). Pull the latest
# binary → ~/.local/bin, which precedes /usr/bin in PATH so it wins.
if [[ -x "$HOME/.local/bin/fzf" ]]; then
    skip "fzf already installed → ~/.local/bin ($("$HOME/.local/bin/fzf" --version 2>/dev/null))."
else
    case "$(uname -m)" in
        x86_64)        farch="linux_amd64" ;;
        aarch64|arm64) farch="linux_arm64" ;;
        *) warn "Unsupported arch $(uname -m) for the fzf prebuilt binary."; farch="" ;;
    esac
    ftag="$([[ -n "$farch" ]] && curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest 2>/dev/null \
        | awk -F'"' '/"tag_name"/ {print $4; exit}')"
    if [[ -z "$farch" || -z "$ftag" ]]; then
        warn "Skipping fzf — couldn't resolve a release; the z/Z picker needs fzf ≥ 0.45."
    else
        furl="https://github.com/junegunn/fzf/releases/download/${ftag}/fzf-${ftag#v}-${farch}.tar.gz"
        ftmp="/tmp/fzf.$$.tgz"
        step "Installing fzf ${ftag} ($farch)"
        run mkdir -p "$HOME/.local/bin"
        run curl -fL --progress-bar -o "$ftmp" "$furl"
        run tar -xzf "$ftmp" -C "$HOME/.local/bin" fzf
        run chmod +x "$HOME/.local/bin/fzf"
        run rm -f "$ftmp"
        ok "fzf ${ftag} installed → ~/.local/bin."
    fi
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

# ── 5a. tmux-run helper — run yazi's ':' command in a tmux split ─────────────
# ':' routes the typed command through this so it lands in a split at yazi's
# cwd (pane stays open, aliases resolved); outside tmux it runs inline.
tmux_run="$HOME/.config/yazi/scripts/tmux-run.sh"
if [[ -f "$tmux_run" ]]; then
    skip "tmux-run.sh helper already installed."
else
    step "Installing tmux-run.sh helper for the ':' keybind"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s tmux-run.sh → %s\n' "$C_DIM" "$C_OFF" "$tmux_run"
    else
        mkdir -p "$(dirname "$tmux_run")"
        cat > "$tmux_run" <<'SH'
#!/usr/bin/env bash
# Run a command from yazi in a tmux split at yazi's cwd; the pane stays open as
# an interactive shell. Outside tmux, run it inline. Command comes via env to
# dodge quoting, and -i loads the rc so aliases resolve.
cmd="$*"
[[ -z "$cmd" ]] && exit 0
shell="${SHELL:-/bin/sh}"
if [[ -n "${TMUX:-}" ]]; then
    tmux split-window -h -c "$PWD" -e "YAZI_CMD=$cmd" \
        "$shell -ic 'eval \"\$YAZI_CMD\"; exec $shell'"
else
    exec "$shell" -ic "$cmd"
fi
SH
        chmod +x "$tmux_run"
    fi
    ok "tmux-run.sh helper installed."
fi

# ── 5b. tmux-run plugin — clean ':' prompt that calls tmux-run.sh ────────────
# A shell --interactive prefill would show the wrapper path; this plugin prompts
# for just the command, then hands it to tmux-run.sh at the current folder.
tmux_run_plugin="$HOME/.config/yazi/plugins/tmux-run.yazi/main.lua"
if [[ -f "$tmux_run_plugin" ]]; then
    skip "tmux-run.yazi plugin already installed."
else
    step "Installing tmux-run.yazi plugin for the ':' keybind"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s tmux-run.yazi/main.lua → %s\n' "$C_DIM" "$C_OFF" "$tmux_run_plugin"
    else
        mkdir -p "$(dirname "$tmux_run_plugin")"
        cat > "$tmux_run_plugin" <<'LUA'
-- Prompt for a command and run it via tmux-run.sh at the current folder.
-- Keeps the prompt clean (no wrapper path) unlike a shell --interactive prefill.
-- Uses :output() (not :spawn) — yazi kills a spawned child on drop, so the
-- wrapper never runs. tmux split-window returns at once, so this won't block.
local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

return {
	entry = function()
		local cwd = get_cwd()
		local cmd, event = ya.input {
			title = "Run:",
			pos = { "top-center", y = 3, w = 60 },
		}
		if event ~= 1 or not cmd or cmd == "" then
			return
		end
		local out, err = Command(os.getenv("HOME") .. "/.config/yazi/scripts/tmux-run.sh")
			:arg(cmd)
			:cwd(cwd)
			:output()
		if not out then
			ya.err("tmux-run failed: " .. tostring(err))
		end
	end,
}
LUA
    fi
    ok "tmux-run.yazi plugin installed."
fi

# ── 5c. Keymap — open cwd in vim, run commands in a tmux split ───────────────
# `e` launches vim on the cwd (--block hands the terminal over; :q returns).
# `:` opens the tmux-run plugin (see 5a/5b).
keymap="$HOME/.config/yazi/keymap.toml"
if [[ -f "$keymap" ]]; then
    skip "yazi keymap.toml exists — leaving keybinds untouched."
else
    step "Adding keybinds — 'e' opens vim, ':' runs a command in a tmux split"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [[mgr.prepend_keymap]] e → vim . / : → plugin tmux-run → %s\n' "$C_DIM" "$C_OFF" "$keymap"
    else
        mkdir -p "$(dirname "$keymap")"
        cat > "$keymap" <<'TOML'
[[mgr.prepend_keymap]]
on   = "e"
run  = 'shell "vim ." --block'
desc = "Open the current directory in vim"

[[mgr.prepend_keymap]]
on   = ":"
run  = "plugin tmux-run"
desc = "Run a command in a tmux split (yazi's cwd)"
TOML
    fi
    ok "yazi keybinds → e opens vim, : runs a command in a tmux split."
fi

# ── 6. git.yazi plugin — per-file git status in the listing ──────────────────
# Needs three pieces: the plugin package, require("git"):setup() in init.lua,
# and the fetchers in yazi.toml that feed git state to each file.
git_plugin_dir="$HOME/.config/yazi/plugins/git.yazi"
if [[ -d "$git_plugin_dir" ]]; then
    skip "git.yazi plugin already installed."
else
    step "Installing git.yazi plugin (ya pkg add)"
    run "$ya" pkg add yazi-rs/plugins:git
    ok "git.yazi plugin installed."
fi

init_lua="$HOME/.config/yazi/init.lua"
if [[ -f "$init_lua" ]] && grep -q 'require("git")' "$init_lua"; then
    skip "init.lua already sets up git plugin."
else
    step "Wiring git plugin setup into init.lua"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would append:%s require("git"):setup() → %s\n' "$C_DIM" "$C_OFF" "$init_lua"
    else
        mkdir -p "$(dirname "$init_lua")"
        printf 'require("git"):setup()\n' >> "$init_lua"
    fi
    ok "init.lua → git plugin enabled."
fi

# The fetchers populate git state per file; without them the plugin shows nothing.
yazi_toml="$HOME/.config/yazi/yazi.toml"
if [[ -f "$yazi_toml" ]] && grep -q 'id = "git"' "$yazi_toml"; then
    skip "yazi.toml already has the git fetchers."
elif [[ -f "$yazi_toml" ]]; then
    warn "yazi.toml exists without git fetchers — add manually under [plugin]:"
    warn '  prepend_fetchers = [{ id = "git", name = "*", run = "git" }, { id = "git", name = "*/", run = "git" }]'
else
    step "Writing git fetchers to yazi.toml"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [plugin] prepend_fetchers (git) → %s\n' "$C_DIM" "$C_OFF" "$yazi_toml"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        cat > "$yazi_toml" <<'TOML'
[plugin]
prepend_fetchers = [
	{ id = "git", name = "*", run = "git" },
	{ id = "git", name = "*/", run = "git" },
]
TOML
    fi
    ok "yazi.toml → git fetchers wired."
fi

ok "Yazi ready."
