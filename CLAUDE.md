# CLAUDE.md

## "Commit" covers the sibling repos too

This repo works hand in hand with the repos it clones, so when I say "commit" (or "push"),
check them all, not only this one:

- every git repo under `~/linux-configuration/` (i3, bash, vim, tmux, …)
- `~/code/skills`

Run `git status` in each. Commit the ones with changes, each with its own message,
following the global commit rules. Push only if my latest message says "push" (see the
global rules). Tell me which repos you touched.

## `./setup.sh` is the command that must always work

When I update or change this machine by hand (install, remove, reconfigure), I always run
`bash ./setup.sh`. It is the one entry point I use, so it must work well every time.

- Every change to this repo must keep `./setup.sh` working: installing, uninstalling
  (the "you unticked these" list), and re-running on a machine already set up.
- A fix in a module (`advanced/*.sh`, `basic/*.sh`) is not done until the path
  `./setup.sh` takes to reach it works too.
- If something can only be fixed by hand, `./setup.sh` is broken: fix the script.

## Tests: `./tests/run.sh`

Everything runs in Docker, so the machine is never touched. Run it on every change.

- `./tests/run.sh` — shellcheck + the bats unit tests (seconds). Must pass on every change.
- `./tests/run.sh e2e` — the real `./setup.sh` in a fresh Ubuntu 26.04 container: install
  an app, untick and uninstall it, re-run. Must pass when `setup.sh`, `lib/`,
  `modules.conf` or a module changes. Logs land in `tests/e2e/logs/`.
- A bug fix gets a test that fails without the fix (see `tests/unit/`). apt, dpkg and sudo
  are faked in `tests/unit/helpers.bash`.
- `BLE_ANSWERS=FILE` answers the lists of `./setup.sh` without a terminal (format in
  `lib/ui.sh`). Tests use it; an answer that matches no row stops the run.
- shellcheck fails on any warning; `.shellcheckrc` says which codes are off and why.
