<!-- playwright-remote (best-linux-environment) -->
## Browser on this machine: the `playwright` and `playwright-remote` MCPs

Two MCPs drive a Firefox from here:

- `playwright` — a headless Firefox on this machine. No screen needed: you see the
  page through snapshots and screenshots, the user sees nothing. Use it by default
  to check a page.
- `playwright-remote` — a visible Firefox window on the screen of the PC that
  ssh'd into this machine, through `ws://127.0.0.1:9323/firefox`, a reverse SSH
  tunnel opened by `b-pw-display` on that PC. Use it when the user wants to watch.

For `playwright-remote`:

- Before the first browser call, check the tunnel: `ss -Hltn 'sport = :9323' | grep -q .`
- Tunnel down, or a tool fails with "connect ECONNREFUSED 127.0.0.1:9323": tell the
  user to leave this ssh session and reconnect from their PC with
  `b-pw-display <user>@<this host>` (it opens Firefox there and ssh's in with the tunnel).
  Until then, `playwright` works without it.
- Their PC has no `b-pw-display`: tell them to install the `playwright-mcp` module
  of best-linux-environment there (`./setup.sh`, tick it). It needs a desktop session
  and node/npx.
- "Playwright version mismatch": both sides use `@playwright/mcp@latest`; tell the user
  to reconnect with `b-pw-display` (it re-fetches latest) and restart this agent.

`playwright` fails with "Browser "firefox" is not installed" or a missing library:
re-run `./setup.sh` in best-linux-environment (it installs the build and its libraries).
<!-- /playwright-remote -->
