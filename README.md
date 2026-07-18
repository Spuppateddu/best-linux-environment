# best-linux-environment

Commands to replicate my personal Ubuntu setup on a fresh **Ubuntu 26.04 LTS**.

One entry point, `install.sh`, orchestrates everything. It's **idempotent**:
re-run it any time and it only does the missing work — so adding a new package
or app to this repo and re-running is all it takes to bring an existing machine
up to date.

## Quick start

```bash
git clone https://github.com/Spuppateddu/best-linux-environment.git ~/best-linux-environment
cd ~/best-linux-environment
./install.sh            # basic setup, pick tools + advanced apps from menus
```

The repo is expected to live at `~/best-linux-environment`; every tool config
repo it manages lives **hidden in `$HOME`** (`~/.zsh`, `~/.vim`, `~/.tmuxrc`,
`~/.alacritty`, `~/.i3rc`).

Preview without changing anything:

```bash
./install.sh --dry-run all
```

## Modes

| Command | Does |
| --- | --- |
| `./install.sh` | Basic setup + tool menu, then advanced-apps menu, then offers the boot cron |
| `./install.sh basic` | Only the essentials (base, tools, fonts, …) |
| `./install.sh advanced` | Only the advanced-apps menu |
| `./install.sh advanced steam okular` | Install named advanced apps directly |
| `./install.sh all` | Basic + **every** tool + **every** advanced app, no prompts |
| `./install.sh update` | Non-interactive: pull this repo + every installed tool repo, re-apply configs |
| `./install.sh cron` | (Re)install the `@reboot` auto-update cron |
| `./install.sh --dry-run <mode>` | Preview only — touches nothing |

## Tool config repos

The 5 tool configs each live in **their own repo**, cloned hidden into `$HOME`
(list in [`tools.conf`](tools.conf)):

| Tool | Repo | Clone dest |
| --- | --- | --- |
| zsh | [`zshrc`](https://github.com/Spuppateddu/zshrc) | `~/.zsh` |
| vim | [`vimrc`](https://github.com/Spuppateddu/vimrc) | `~/.vim` |
| tmux | [`tmuxrc`](https://github.com/Spuppateddu/tmuxrc) | `~/.tmuxrc` |
| alacritty | [`alacritty-config`](https://github.com/Spuppateddu/alacritty-config) | `~/.alacritty` |
| i3 | [`i3rc`](https://github.com/Spuppateddu/i3rc) | `~/.i3rc` |

**This repo does not know how to install any of them.** Each tool repo ships
its own idempotent `install.sh` (deps, wiring, plugin install, live reload);
`basic/10-tools.sh` only clones/updates each repo and calls that script.

You choose what to install: already-cloned tools are always pulled and
re-applied, missing ones are offered in a menu (pick numbers, `all`, or `q`
for none). `./install.sh all` installs every tool without asking.

## Auto-update at boot

At the end of the first interactive install you're asked once whether to add a
`@reboot` cron. If you accept, every boot runs `install.sh update`, which:

1. `git pull`s **this repo** (and re-execs itself if it changed);
2. runs every basic module, which `git pull`s each **installed** tool repo and
   re-runs its `install.sh` — so new configs are applied and, where possible,
   reloaded live (tmux `source-file`, i3 `i3-msg reload`; zsh applies on the
   next `exec zsh`/new terminal);
3. logs to `~/.cache/best-linux-environment/update.log`.

Cron runs have no terminal, so anything needing `sudo` (new apt packages) is
skipped with a warning — run `./install.sh` from a terminal to pick those up.
If you decline, that's remembered (asked only once); update by hand with
`./install.sh update`, or add the cron later with `./install.sh cron`.

## What "basic" installs

Run in order (`basic/NN-*.sh`); order matters — the base tooling exists before
the tool repos install into it, and fonts before the tools that render them.

1. **`00-base`** — core apt tooling (git, curl, build-essential, `zsh`, …).
2. **`10-tools`** — the tool config repos described above: clone/update each
   into its hidden `$HOME` folder and run **its own** `install.sh`.
3. **`50-fonts-cursor`** — cross-cutting **Nerd Font + macOS cursor**,
   owned here so the per-tool repos stay light.
4. **`55-yazi`** — [Yazi](https://github.com/sxyazi/yazi) TUI file manager
   (prebuilt binary → `~/.local/bin`) with in-terminal image/video/PDF preview.
   Alacritty has no graphics protocol, so preview goes through **ueberzugpp**
   (installed as a `.deb` from its OBS repo) plus `ffmpegthumbnailer`/`poppler`.
   yazi auto-detects ueberzugpp — no `yazi.toml` needed. Runs after the Nerd
   Font so its icons render. Ships the **gruvbox-dark** flavor (`ya pkg add
   bennyyip/gruvbox-dark`) wired in `~/.config/yazi/theme.toml`. Also installs
   **zoxide** (apt) and the latest **fzf** binary (→ `~/.local/bin`) for the
   `z`/`Z` bindings — apt's fzf 0.44 renders the picker blank under yazi.
5. **`60-flameshot`** — screenshot tool (i3's `$mod+Shift+s`); apt package.
6. **`70-zen-browser`** — [Zen](https://zen-browser.app) via its official
   user-local script (no root/apt; installs to `~/.local/bin/zen`).
7. **`80-arandr`** — GUI for xrandr (monitor layout); apt package.
8. **`90-opencode`** — [opencode](https://opencode.ai) terminal AI coding agent
   via its official user-local script (installs to `~/.local/bin/opencode`).
   Sets the built-in **gruvbox** theme in `~/.config/opencode/tui.json`.

### Design: light repos, one orchestrator

Each tool keeps its own repo (`~/.zsh`, `~/.vim`, `~/.tmuxrc`, `~/.alacritty`,
`~/.i3rc`) and **its own install logic** — an idempotent `install.sh` at the
repo root that installs deps, wires configs, and reloads live where possible.
This repo only clones/updates them (per `tools.conf`) and calls that script;
it never reimplements a tool's install. Anything cross-cutting that would
otherwise bloat a single repo — the cursor theme, the shared Nerd Font — lives
**here** instead (`i3rc/setup.sh` no longer carries its own copies).

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
- **Config repos are pulled, then reloaded.** On every re-run (or boot-cron
  `update`) each installed `~/.zsh`, `~/.vim`, `~/.tmuxrc`, `~/.alacritty`,
  `~/.i3rc` is `git pull`ed and its own `install.sh` re-applied live where
  possible — tmux via `source-file`, i3 via `i3-msg reload`, alacritty
  auto-reloads. zsh can't reload the parent shell, so it prints `exec zsh`; vim
  loads on next launch.
- Third-party repos resolve the Ubuntu release at runtime (`lsb_release`), so
  nothing is hardcoded to a codename. If MEGA hasn't published an `xUbuntu_26.04`
  build yet, that module warns and points to the manual `.deb`.
- Everything is safe to re-run.
