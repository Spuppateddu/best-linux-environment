#!/usr/bin/env bats
# advanced/playwright-mcp.sh, with claude and npx faked.

load helpers

# A claude that logs `mcp add` and keeps ~/.claude.json valid.
fake_claude() {
    mkdir -p "$HOME/.local/bin"
    printf '#!/usr/bin/env bash\necho "claude $*" >> "$FAKE_LOG"\n' > "$HOME/.local/bin/claude"
    chmod +x "$HOME/.local/bin/claude"
    echo '{}' > "$HOME/.claude.json"
}

@test "playwright-mcp: desktop entry is --isolated, so two agents can open Firefox at once" {
    export BLE_PROFILE=desktop
    pkg_status nodejs installed; pkg_status npm installed
    fake_cmd npx 'exit 0'
    fake_claude
    run bash "$REPO/advanced/playwright-mcp.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -q '^claude mcp add -s user playwright -- npx .* --isolated' "$FAKE_LOG"
    ! grep -q -- '--user-data-dir' "$FAKE_LOG"
}

@test "playwright-mcp: server gets a headless Firefox and its libraries, next to playwright-remote" {
    export BLE_PROFILE=server
    pkg_status nodejs installed; pkg_status npm installed
    fake_cmd npx 'echo "npx $*" >> "$FAKE_LOG"'
    fake_claude
    run bash "$REPO/advanced/playwright-mcp.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -q '^npx -y @playwright/mcp@latest install-browser firefox' "$FAKE_LOG"
    grep -q '^claude mcp add -s user playwright -- npx .* --browser firefox --headless .* --isolated' "$FAKE_LOG"
    grep -q '^claude mcp add -s user playwright-remote -- npx .* --endpoint ws://127.0.0.1:9323/firefox' "$FAKE_LOG"
    grep -q '^apt-get install -y libgtk-3-0t64 libasound2t64 libxdamage1 fonts-liberation$' "$FAKE_LOG"
    grep -q '^## Browser on this machine: the `playwright` and `playwright-remote` MCPs' "$HOME/.claude/CLAUDE.md"
}

@test "playwright-mcp: a server set up before the headless browser still counts as installed" {
    export BLE_PROFILE=server
    echo '{"mcpServers":{"playwright-remote":{"args":[]}}}' > "$HOME/.claude.json"
    run bash "$REPO/advanced/playwright-mcp.sh" --check
    [ "$status" -eq 0 ]
}
