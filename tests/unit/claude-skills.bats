#!/usr/bin/env bats
# advanced/claude-code.sh and advanced/skills.sh, with curl and git faked.

load helpers

# A git whose `clone URL DEST` makes DEST a checkout holding global-rules.md.
fake_git() {
    fake_cmd git 'echo "git $*" >> "$FAKE_LOG"
        [[ "$1" == clone ]] && { d="${!#}"; mkdir -p "$d/.git"; touch "$d/global-rules.md"; }
        exit 0'
}

@test "skills: a fresh machine gets the clone, the link and the import" {
    pkg_status git installed
    fake_git
    run bash "$REPO/advanced/skills.sh" </dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -q '^git clone .*Spuppateddu/skills.git' "$FAKE_LOG"
    [ -d "$HOME/code/skills/.git" ]
    [ "$(readlink "$HOME/.claude/skills")" = "$HOME/code/skills" ]
    grep -qx '@~/code/skills/global-rules.md' "$HOME/.claude/CLAUDE.md"
    run bash "$REPO/advanced/skills.sh" --check
    [ "$status" -eq 0 ]
}

@test "skills: a clone already there is not pulled or cloned again" {
    pkg_status git installed
    fake_git
    mkdir -p "$HOME/code/skills/.git"
    echo mine > "$HOME/code/skills/local-change"
    run bash "$REPO/advanced/skills.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q '^git ' "$FAKE_LOG"
    [ "$(cat "$HOME/code/skills/local-change")" = mine ]
}

@test "skills: re-run keeps CLAUDE.md as it is, the import only once" {
    pkg_status git installed
    fake_git
    mkdir -p "$HOME/.claude"
    printf '# my rules\n@%s/code/skills/global-rules.md\n' "$HOME" > "$HOME/.claude/CLAUDE.md"
    run bash "$REPO/advanced/skills.sh" </dev/null
    run bash "$REPO/advanced/skills.sh" </dev/null
    [ "$status" -eq 0 ]
    [ "$(grep -c 'global-rules.md' "$HOME/.claude/CLAUDE.md")" -eq 1 ]
    grep -qx '# my rules' "$HOME/.claude/CLAUDE.md"
}

@test "skills: a real ~/.claude/skills folder is backed up, not lost" {
    pkg_status git installed
    fake_git
    mkdir -p "$HOME/.claude/skills/old-skill"
    run bash "$REPO/advanced/skills.sh" </dev/null
    [ "$status" -eq 0 ]
    [ -L "$HOME/.claude/skills" ]
    compgen -G "$HOME/.claude/skills.backup.*/old-skill" >/dev/null
}

@test "skills --uninstall: drops the link and the import, keeps the clone and the rest" {
    mkdir -p "$HOME/code/skills/.git" "$HOME/.claude"
    ln -s "$HOME/code/skills" "$HOME/.claude/skills"
    printf '# my rules\n@~/code/skills/global-rules.md\n<!-- note -->\n' > "$HOME/.claude/CLAUDE.md"
    run bash "$REPO/advanced/skills.sh" --uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.claude/skills" ]
    ! grep -q global-rules "$HOME/.claude/CLAUDE.md"
    grep -qx '# my rules' "$HOME/.claude/CLAUDE.md"
    grep -qx '<!-- note -->' "$HOME/.claude/CLAUDE.md"
    [ -d "$HOME/code/skills/.git" ]
    run bash "$REPO/advanced/skills.sh" --check
    [ "$status" -eq 1 ]
}

@test "claude-code: installs through claude.ai/install.sh, then a re-run skips it" {
    pkg_status curl installed
    fake_cmd curl 'echo "curl $*" >> "$FAKE_LOG"
        echo "mkdir -p \"\$HOME/.local/bin\"; printf \"#!/bin/sh\\n\" > \"\$HOME/.local/bin/claude\"; chmod +x \"\$HOME/.local/bin/claude\""'
    run bash "$REPO/advanced/claude-code.sh" </dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -q '^curl .*claude.ai/install.sh' "$FAKE_LOG"
    [ -x "$HOME/.local/bin/claude" ]
    : > "$FAKE_LOG"
    run bash "$REPO/advanced/claude-code.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q '^curl' "$FAKE_LOG"
}

@test "claude-code --uninstall: removes the binary and its versions, keeps ~/.claude" {
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/claude/versions" "$HOME/.claude"
    printf '#!/bin/sh\n' > "$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"
    echo '{}' > "$HOME/.claude.json"
    run bash "$REPO/advanced/claude-code.sh" --uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.local/bin/claude" ]
    [ ! -e "$HOME/.local/share/claude" ]
    [ -d "$HOME/.claude" ] && [ -f "$HOME/.claude.json" ]
}
