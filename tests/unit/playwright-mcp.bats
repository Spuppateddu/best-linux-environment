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
