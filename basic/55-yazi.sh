#!/usr/bin/env bash
# Yazi — TUI file manager with preview inside Alacritty. Prebuilt binary from
# GitHub, plus ueberzugpp (a .deb from OBS) for images, which yazi auto-detects.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Yazi"

# ── 1. Preview backends + navigation ──────────────────────────────────────────
# fzf is not from apt (0.44 paints blank inside yazi); 26.04 renamed p7zip-full.
sevenzip=p7zip-full
apt_has_candidate 7zip && sevenzip=7zip
apt_ensure ffmpegthumbnailer poppler-utils unar "$sevenzip" curl unzip git zoxide

# ── 2. ueberzugpp — image overlay for terminals without a graphics protocol ───
if has_cmd ueberzugpp; then
    skip "ueberzugpp already installed."
else
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    release="$(lsb_release -rs 2>/dev/null || echo '')"
    base="https://download.opensuse.org/repositories/home:/justkidding/xUbuntu_${release}"
    # The .deb filename comes from the repo index, so it stays version-proof. The
    # `|| true` is load-bearing: without it an offline curl exits the module here.
    deb_path="$(curl -fsSL "$base/Packages" 2>/dev/null \
        | awk -v a="$arch" '$1=="Filename:" && $2 ~ ("^" a "/") {print $2; exit}' || true)"
    if [[ -z "$release" || -z "$deb_path" ]]; then
        warn "No ueberzugpp build for xUbuntu_${release:-?}/${arch} — image preview disabled."
        warn "Grab it manually from https://github.com/jstkdng/ueberzugpp/releases."
    elif [[ "$DRY_RUN" != true ]] && ! can_sudo; then
        # Guard like apt_ensure does, or the boot cron fails at the sudo below
        # and `set -e` takes the rest of this module with it at every boot.
        warn "sudo unavailable (non-interactive) — skipped the ueberzugpp .deb."
        warn "Run ./setup.sh from a terminal to pick it up."
    else
        # tmp_file matters most here: this path goes to `sudo apt-get install`,
        # so a guessable name would let someone else's symlink decide what root installs.
        tmp="$(tmp_file .deb)"
        step "Installing ueberzugpp ($arch) from OBS"
        # A condition, not run bare: ueberzugpp only buys image preview, so a
        # failure warns instead of aborting. apt, not dpkg, so deps resolve.
        if run curl -fL --progress-bar -o "$tmp" "$base/$deb_path" \
           && run sudo apt-get install -y "$tmp"; then
            ok "ueberzugpp installed."
        else
            warn "ueberzugpp install failed — image preview disabled, continuing."
        fi
        run rm -f "$tmp"
    fi
fi

# ── 3. Yazi binary — prebuilt release → ~/.local/bin ─────────────────────────
# The zip always carries the newest build, so re-running this IS the upgrade.
install_yazi_bin() {
    local ytarget url tmp ext
    ytarget="$(arch_pick x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu)" || {
        fail "Unsupported arch $(uname -m) for the yazi prebuilt binary."
        return 1
    }
    url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${ytarget}.zip"
    tmp="$(tmp_file .zip)"; ext="$(tmp_dir)"
    run mkdir -p "$HOME/.local/bin"
    # A condition, not run bare: on the boot cron a failed download must not take
    # the module down, least of all when a working yazi is already here.
    if run curl -fL --progress-bar -o "$tmp" "$url" \
       && run unzip -oq "$tmp" -d "$ext" \
       && run install -m755 "$ext/yazi-${ytarget}/yazi" "$HOME/.local/bin/yazi" \
       && run install -m755 "$ext/yazi-${ytarget}/ya"   "$HOME/.local/bin/ya"; then
        run rm -rf "$tmp" "$ext"
        return 0
    fi
    run rm -rf "$tmp" "$ext"
    return 1
}

# Asked by path, since the boot cron's PATH lacks ~/.local/bin. `|| true` so a
# binary too broken to print its version yields empty — gh_newer_tag then skips it.
yazi_version() { "$HOME/.local/bin/yazi" --version 2>/dev/null | awk '{print $2; exit}' || true; }

if ! have_local_bin yazi && ! has_cmd yazi; then
    step "Installing yazi"
    if install_yazi_bin; then
        ok "yazi installed → ~/.local/bin (open with: yazi)."
    else
        fail "Could not install yazi — retried on the next run."
    fi
elif ! have_local_bin yazi; then
    # Came from apt or cargo — whoever installed it owns updating it.
    skip "yazi already installed (not ours to upgrade — not in ~/.local/bin)."
elif want_upgrade; then
    have="$(yazi_version)"
    if newer="$(gh_newer_tag sxyazi/yazi "$have")"; then
        step "Upgrading yazi ${have:-?} → ${newer}"
        install_yazi_bin && ok "yazi upgraded to ${newer}." \
            || warn "Could not upgrade yazi — keeping ${have:-the current build}."
    else
        skip "yazi ${have:-present} — nothing newer to install."
    fi
else
    skip "yazi already installed (${have:-$(yazi_version)}) — ./boot.sh upgrades it."
fi

# ── 3b. fzf — interactive picker for the z/Z bindings ────────────────────────
# apt's 0.44 paints nothing when yazi pipes its stdout, so take the latest binary.
install_fzf_bin() {
    local tag="$1" farch furl
    farch="$(arch_pick linux_amd64 linux_arm64)" || {
        warn "Unsupported arch $(uname -m) for the fzf prebuilt binary."
        return 1
    }
    furl="https://github.com/junegunn/fzf/releases/download/${tag}/fzf-${tag#v}-${farch}.tar.gz"
    install_tarball_bin "$furl" fzf
}

# `fzf --version` prints "0.65.0 (abc1234)". `|| true` for the reason above.
fzf_version() { "$HOME/.local/bin/fzf" --version 2>/dev/null | awk '{print $1; exit}' || true; }

if ! have_local_bin fzf; then
    if ftag="$(gh_latest_tag junegunn/fzf)"; then
        step "Installing fzf ${ftag}"
        install_fzf_bin "$ftag" && ok "fzf ${ftag} installed → ~/.local/bin." \
            || warn "Could not download fzf ${ftag} — the z/Z picker will be unavailable."
    else
        warn "Skipping fzf — couldn't resolve a release; the z/Z picker needs fzf ≥ 0.45."
    fi
elif want_upgrade; then
    have="$(fzf_version)"
    if newer="$(gh_newer_tag junegunn/fzf "$have")"; then
        step "Upgrading fzf ${have:-?} → ${newer}"
        install_fzf_bin "$newer" && ok "fzf upgraded to ${newer}." \
            || warn "Could not upgrade fzf — keeping ${have:-the current build}."
    else
        skip "fzf ${have:-present} — nothing newer to install."
    fi
else
    skip "fzf already installed → ~/.local/bin ($(fzf_version)) — ./boot.sh upgrades it."
fi

# ── 4. Gruvbox flavor — installed via ya, wired in theme.toml ─────────────────
# `ya` ships in yazi's zip, so an apt/cargo yazi has none: resolve, never assume.
ya=""
if has_cmd ya; then
    ya="ya"
elif [[ -x "$HOME/.local/bin/ya" || "$DRY_RUN" == true ]]; then
    ya="$HOME/.local/bin/ya"
fi

# ya_pkg_add PKG DEST LABEL  — install a yazi package, tolerating failure: run bare,
# an offline boot took the whole module down. Non-zero when it is not on disk after.
ya_pkg_add() {
    local pkg="$1" dest="$2" label="$3"
    [[ -d "$dest" ]] && { skip "$label already installed."; return 0; }
    [[ "$DRY_RUN" == true ]] && { printf '%s  would run:%s %s pkg add %s\n' "$C_DIM" "$C_OFF" "$ya" "$pkg"; return 0; }
    if [[ -z "$ya" ]]; then
        warn "yazi's 'ya' helper is not installed — skipped $label."
        return 1
    fi
    step "Installing $label (ya pkg add $pkg)"
    if "$ya" pkg add "$pkg"; then
        ok "$label installed."
        return 0
    fi
    warn "Could not install $label (offline?) — continuing without it."
    return 1
}

flavor_dir="$HOME/.config/yazi/flavors/gruvbox-dark.yazi"
flavor_ok=true
ya_pkg_add bennyyip/gruvbox-dark "$flavor_dir" "gruvbox-dark flavor" || flavor_ok=false

theme="$HOME/.config/yazi/theme.toml"
if [[ "$flavor_ok" != true ]]; then
    # Naming a flavor that isn't on disk makes yazi reject the whole config —
    # worse than having no theme.toml at all.
    skip "gruvbox-dark not installed — not writing theme.toml (retried next run)."
else
    # --seed: which flavor you run is a preference, so only ./setup.sh puts
    # gruvbox-dark back.
    config_write "$theme" --seed <<'TOML'
[flavor]
dark = "gruvbox-dark"
TOML
fi

# ── 5a. tmux-run helper — run yazi's ':' command in a tmux split ─────────────
# Code, not preference, so it is managed: a fix here reaches every machine.
tmux_run="$HOME/.config/yazi/scripts/tmux-run.sh"
config_write "$tmux_run" --exec <<'SH'
#!/usr/bin/env bash
# Run a command from yazi in a tmux split at its cwd, or inline outside tmux.
# The command comes via env to dodge quoting; -i loads the rc so aliases resolve.
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

# ── 5b. tmux-run plugin — clean ':' prompt that calls tmux-run.sh ────────────
# A shell --interactive prefill would show the wrapper path; this prompts clean.
tmux_run_plugin="$HOME/.config/yazi/plugins/tmux-run.yazi/main.lua"
config_write "$tmux_run_plugin" <<'LUA'
-- Prompt for a command and run it via tmux-run.sh at the current folder.
-- :output(), not :spawn — yazi kills a spawned child on drop. It won't block.
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

# ── 5c. Keymap — open cwd in vim, run commands in a tmux split ───────────────
# --seed: keybinds are the first thing anyone rebinds, so yours survive a boot.
keymap="$HOME/.config/yazi/keymap.toml"
config_write "$keymap" --seed <<'TOML'
[[mgr.prepend_keymap]]
on   = "e"
run  = 'shell "vim ." --block'
desc = "Open the current directory in vim"

[[mgr.prepend_keymap]]
on   = ":"
run  = "plugin tmux-run"
desc = "Run a command in a tmux split (yazi's cwd)"
TOML

# ── 6. git.yazi plugin — per-file git status in the listing ──────────────────
# Three pieces: the package, require("git"):setup() in init.lua, and the fetchers.
git_plugin_dir="$HOME/.config/yazi/plugins/git.yazi"
git_plugin_ok=true
ya_pkg_add yazi-rs/plugins:git "$git_plugin_dir" "git.yazi plugin" || git_plugin_ok=false

# Both reference the plugin by name, so writing either without it on disk makes
# yazi error at launch. Skipping keeps the config valid for the next run.
if [[ "$git_plugin_ok" != true ]]; then
    skip "git.yazi not installed — skipping its init.lua and fetcher wiring (retried next run)."
else

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

# Yazi >26.1.22 renamed `name`→`url` and made `group` mandatory, so a stale block
# no longer parses. It is migrated in place, keeping the old file as .bak.
yazi_toml="$HOME/.config/yazi/yazi.toml"
fetchers_toml=$(cat <<'TOML'
[[plugin.prepend_fetchers]]
url   = "*"
run   = "git"
group = "git"

[[plugin.prepend_fetchers]]
url   = "*/"
run   = "git"
group = "git"
TOML
)

if [[ -f "$yazi_toml" ]] && grep -q 'group = "git"' "$yazi_toml"; then
    skip "yazi.toml already has the git fetchers."
elif [[ -f "$yazi_toml" ]] && grep -q 'prepend_fetchers' "$yazi_toml"; then
    step "Migrating yazi.toml git fetchers to the url/group syntax"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would rewrite:%s legacy [[plugin.prepend_fetchers]] → url/group → %s\n' "$C_DIM" "$C_OFF" "$yazi_toml"
    else
        cp -f "$yazi_toml" "$yazi_toml.bak"
        # Drop the legacy fetchers in both spellings — inline array and table —
        # then squeeze the blank lines they leave behind.
        awk '
            /^[[:space:]]*prepend_fetchers[[:space:]]*=/ { arr = 1; next }
            arr { if (/\]/) arr = 0; next }
            /^[[:space:]]*\[\[plugin\.prepend_fetchers\]\]/ { tbl = 1; next }
            tbl {
                if (/^[[:space:]]*$/ || /^[[:space:]]*\[/) { tbl = 0 } else next
            }
            { print }
        ' "$yazi_toml.bak" | cat -s > "$yazi_toml"
        # A file that held nothing but fetchers is left with a bare [plugin] header.
        [[ "$(tr -d '[:space:]' < "$yazi_toml")" == "[plugin]" ]] && : > "$yazi_toml" || true
        [[ -s "$yazi_toml" ]] && printf '\n' >> "$yazi_toml" || true
        printf '%s\n' "$fetchers_toml" >> "$yazi_toml"
    fi
    ok "yazi.toml → git fetchers migrated (old file kept as yazi.toml.bak)."
else
    step "Writing git fetchers to yazi.toml"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [[plugin.prepend_fetchers]] (git) → %s\n' "$C_DIM" "$C_OFF" "$yazi_toml"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        printf '%s\n' "$fetchers_toml" > "$yazi_toml"
    fi
    ok "yazi.toml → git fetchers wired."
fi

fi   # end: git.yazi installed

# ── 6b. Enter on an image opens Firefox ──────────────────────────────────────
# orphan = true or quitting yazi closes the browser. Appended, not written whole.
yazi_toml="$HOME/.config/yazi/yazi.toml"
opener_toml=$(cat <<'TOML'
[opener]
image = [
	{ run = 'firefox "$@"', orphan = true, desc = "Firefox", for = "unix" },
]

[open]
prepend_rules = [
	{ mime = "image/*", use = "image" },
]
TOML
)

if [[ -f "$yazi_toml" ]] && grep -q '^\[opener\]' "$yazi_toml"; then
    skip "yazi.toml already has an [opener] block — leaving the image rule to you."
else
    step "Wiring the Firefox image opener into yazi.toml"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would append:%s [opener]/[open] (images → firefox) → %s\n' "$C_DIM" "$C_OFF" "$yazi_toml"
    else
        mkdir -p "$(dirname "$yazi_toml")"
        [[ -s "$yazi_toml" ]] && printf '\n' >> "$yazi_toml"
        printf '%s\n' "$opener_toml" >> "$yazi_toml"
    fi
    ok "yazi.toml → Enter on an image opens Firefox."
fi

# ── 7. Keep the yazi packages current ────────────────────────────────────────
# `ya pkg add` only installs, so without this the packages never move. ./boot.sh only.
if want_upgrade && [[ -n "$ya" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s %s pkg upgrade\n' "$C_DIM" "$C_OFF" "$ya"
    else
        step "Upgrading the installed yazi packages (ya pkg upgrade)"
        "$ya" pkg upgrade && ok "yazi packages up to date." \
            || warn "Could not upgrade the yazi packages (offline?) — continuing."
    fi
fi

# Config errors are silent until launch, so parse-check here: `yazi --version`
# reads the config. </dev/null keeps its "Press <Enter>" from blocking the install.
yazi_bin="$HOME/.local/bin/yazi"
has_cmd yazi && yazi_bin="yazi"
if [[ "$DRY_RUN" != true ]] && command -v "$yazi_bin" >/dev/null 2>&1; then
    if ! "$yazi_bin" --version </dev/null >/dev/null 2>&1; then
        warn "yazi rejects its config — it will start with preset settings. Details:"
        "$yazi_bin" --version </dev/null 2>&1 | sed 's/^/    /' || true
    fi
fi

ok "Yazi ready."
