<!-- playwright-remote (best-linux-environment) -->
## Browser on this machine: the `playwright-remote` MCP

No browser runs here. The `playwright-remote` MCP drives a Firefox window on the
screen of the PC that ssh'd into this machine, through `ws://127.0.0.1:9323/firefox`
— a reverse SSH tunnel opened by `b-pw-display` on that PC.

- Before the first browser call, check the tunnel: `ss -Hltn 'sport = :9323' | grep -q .`
- Tunnel down, or a tool fails with "connect ECONNREFUSED 127.0.0.1:9323": tell the
  user to leave this ssh session and reconnect from their PC with
  `b-pw-display <user>@<this host>` (it opens Firefox there and ssh's in with the tunnel).
- Their PC has no `b-pw-display`: tell them to install the `playwright-display` module
  of best-linux-environment there (`./setup.sh`, tick it). It needs a desktop session
  and node/npx.
- "Playwright version mismatch": both sides use `@playwright/mcp@latest`; tell the user
  to reconnect with `b-pw-display` (it re-fetches latest) and restart this agent.
- Do not install a browser here as a workaround unless the user asks.
<!-- /playwright-remote -->
