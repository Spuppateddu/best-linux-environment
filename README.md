# best-linux-environment

Commands to replicate my personal Ubuntu setup on a fresh **Ubuntu 26.04 LTS**.

One entry point, `install.sh`, orchestrates everything. It's **idempotent**:
re-run it any time and it only does the missing work — so adding a new package
or app to this repo and re-running is all it takes to bring an existing machine
up to date.

## Quick start

```bash
git clone https://github.com/Spuppateddu/best-linux-environment.git
cd best-linux-environment
./install.sh            # basic setup, then pick advanced apps from a menu
```

Preview without changing anything:

```bash
./install.sh --dry-run all
```

## Modes

| Command | Does |
| --- | --- |
| `./install.sh` | Basic setup, then an interactive menu to pick advanced apps |
| `./install.sh basic` | Only the essentials |
| `./install.sh advanced` | Only the advanced-apps menu |
| `./install.sh advanced steam okular` | Install named advanced apps directly |
| `./install.sh all` | Basic **+ every** advanced app, no prompts |
| `./install.sh --dry-run <mode>` | Preview only — touches nothing |

## What "basic" installs

Run in order (`basic/NN-*.sh`); order matters — the shell exists before the
config repos are cloned into it.

1. **`00-base`** — core apt tooling (git, curl, build-essential, `zsh`, …).
2. **`10-zsh`** — Oh My Zsh **first**, then its plugins, **then** clones
   [`zshrc`](https://github.com/Spuppateddu/zshrc) into `~/.zsh` and makes zsh
   the login shell.
3. **`20-vim`** — deps + clones [`vimrc`](https://github.com/Spuppateddu/vimrc)
   into `~/.vim`, installs plugins headlessly.
4. **`30-tmux`** — deps + TPM + clones
   [`tmuxrc`](https://github.com/Spuppateddu/tmuxrc) into `~/.tmuxrc`.
5. **`35-alacritty`** — apt package + clones
   [`alacritty-config`](https://github.com/Spuppateddu/alacritty-config) into
   `~/.alacritty` and links its `alacritty.toml` into `~/.config/alacritty`
   (the terminal i3 launches; `i3rc` does not install it).
6. **`40-i3`** — clones [`i3rc`](https://github.com/Spuppateddu/i3rc) into
   `~/.i3rc` and delegates to **its own** `setup.sh` (this repo does not
   reimplement i3's install).
7. **`50-fonts-cursor`** — cross-cutting **Nerd Font + BreezeX-Dark cursor**,
   owned here so the per-tool repos stay light.
8. **`55-yazi`** — [Yazi](https://github.com/sxyazi/yazi) TUI file manager
   (prebuilt binary → `~/.local/bin`) with in-terminal image/video/PDF preview.
   Alacritty has no graphics protocol, so preview goes through **ueberzugpp**
   (installed as a `.deb` from its OBS repo) plus `ffmpegthumbnailer`/`poppler`.
   yazi auto-detects ueberzugpp — no `yazi.toml` needed. Runs after the Nerd
   Font so its icons render.
9. **`60-flameshot`** — screenshot tool (i3's `$mod+Shift+s`); apt package.
10. **`70-zen-browser`** — [Zen](https://zen-browser.app) via its official
   user-local script (no root/apt; installs to `~/.local/bin/zen`).
11. **`80-arandr`** — GUI for xrandr (monitor layout); apt package.

### Design: light repos, one orchestrator

Each tool keeps its own repo (`~/.zsh`, `~/.vim`, `~/.tmuxrc`, `~/.alacritty`,
`~/.i3rc`) and
its own install logic. This repo only **clones/updates** them and wires them up
per their READMEs. Anything cross-cutting that would otherwise bloat a single
repo — the cursor theme, the shared Nerd Font — lives **here** instead.

> The font/cursor blocks still present in `i3rc/setup.sh` are now duplicated by
> `basic/50-fonts-cursor.sh`. They're idempotent (both skip when already
> installed), so the overlap is harmless; `i3rc` can drop them later to slim
> down.

## What "advanced" installs

Optional apps, each a standalone script in `advanced/`. The interactive menu
lists **only apps that aren't installed yet** — already-present ones are hidden.

**To add one, drop a `advanced/<name>.sh` file** that:

- sources `lib/common.sh`;
- defines `is_installed()` (its detection, e.g. `apt_installed <pkg>`);
- answers `--check` up top — `[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }`
  (the menu calls this to decide whether to show it);
- early-exits when `is_installed` so re-runs are no-ops.

It then shows up in the menu automatically on the next run.

| App | Source |
| --- | --- |
| `brave` | [Brave apt repo](https://brave.com/linux/) |
| `xournalpp` | Ubuntu repos |
| `okular` | Ubuntu repos |
| `steam` | multiverse (`steam-installer`) + i386 |
| `tableplus` | [TablePlus apt repo](https://tableplus.com/linux) |
| `megasync` | [MEGA apt repo](https://mega.io/desktop) (`xUbuntu_<release>`) |

## Shared library

`lib/common.sh` holds every reusable helper (colored `step/ok/skip/warn`,
`run` dry-run wrapper, `apt_ensure`, `clone_or_pull`, `link`,
`ensure_source_line`, `apt_repo_add`). Modules source it — no duplicated
plumbing.

## Notes

- **Nothing is reinstalled.** apt packages are checked with `dpkg` first; each
  app/module self-skips when already present.
- **Config repos are pulled, then reloaded.** On re-run each `~/.zsh`, `~/.vim`,
  `~/.tmuxrc`, `~/.alacritty`, `~/.i3rc` is `git pull`ed and applied live where
  possible — tmux via `source-file`, i3 via `i3-msg reload`, alacritty
  auto-reloads. zsh can't reload the parent shell, so it prints `exec zsh`; vim
  loads on next launch.
- Third-party repos resolve the Ubuntu release at runtime (`lsb_release`), so
  nothing is hardcoded to a codename. If MEGA hasn't published an `xUbuntu_26.04`
  build yet, that module warns and points to the manual `.deb`.
- Everything is safe to re-run.
