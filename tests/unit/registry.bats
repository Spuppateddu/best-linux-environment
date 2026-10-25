#!/usr/bin/env bats
# lib/registry.sh on a small fixture, then sanity checks on the real modules.conf.

load helpers

fixture() {
    export BLE_MODULES_CONF="$BATS_TEST_TMPDIR/modules.conf"
    cat > "$BLE_MODULES_CONF" <<'EOF'
# a comment, then a blank line

necessary|tools|all|cmd:faketool|apt:unzip xz-utils+run:basic/05-defaults.sh|unzip and friends
core|desk|gui|path:~/marker|tool:i3|a desktop-only entry
secondary|app|all|script|run:advanced/brave.sh|uses brave.sh for its --uninstall
secondary|noun|all|-|apt:foo|no script, so no --uninstall
bogus|bad|all|-|apt:x|unknown tier
secondary|big|full|-|apt:bar|dropped on minimal only
EOF
}

@test "registry_load: skips comments, drops an unknown tier with a warning" {
    fixture
    BLE_PROFILE=desktop ble 'registry_load; echo "ids=${M_ID[*]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"unknown tier 'bogus'"* ]]
    [[ "$output" == *"ids=tools desk app noun"* ]]
}

@test "registry_load: a server never sees gui entries" {
    fixture
    BLE_PROFILE=server ble 'registry_load; echo "ids=${M_ID[*]}"'
    [[ "$output" == *"ids=tools app noun big"* ]]
}

@test "registry_load: minimal drops gui and full entries" {
    fixture
    BLE_PROFILE=minimal ble 'registry_load; echo "ids=${M_ID[*]}"'
    [[ "$output" == *"ids=tools app noun"* ]]
    [[ "$output" != *big* ]]
}

@test "modules.conf: minimal has no Chrome but keeps playwright-mcp" {
    BLE_PROFILE=minimal ble 'registry_load; echo "ids=${M_ID[*]}"'
    [[ "$output" != *chrome* ]]
    [[ "$output" == *playwright-mcp* ]]
}

@test "mod_actions splits on + only; mod_apt_packages splits the words" {
    fixture
    BLE_PROFILE=desktop ble 'registry_load >/dev/null; mod_actions 0; echo ---; mod_apt_packages 0'
    [ "${lines[0]}" = "apt:unzip xz-utils" ]
    [ "${lines[1]}" = "run:basic/05-defaults.sh" ]
    [ "${lines[3]}" = unzip ]
    [ "${lines[4]}" = xz-utils ]
}

@test "mod_installed: cmd: looks on PATH and in ~/.local/bin" {
    fixture
    BLE_PROFILE=desktop ble 'registry_load; mod_installed 0'
    [ "$status" -eq 1 ]
    mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' > "$HOME/.local/bin/faketool"
    chmod +x "$HOME/.local/bin/faketool"
    BLE_PROFILE=desktop ble 'registry_load; mod_installed 0'
    [ "$status" -eq 0 ]
}

@test "mod_installed: path: expands ~" {
    fixture
    BLE_PROFILE=desktop ble 'registry_load; mod_installed 1'
    [ "$status" -eq 1 ]
    touch "$HOME/marker"
    BLE_PROFILE=desktop ble 'registry_load; mod_installed 1'
    [ "$status" -eq 0 ]
}

@test "mod_installed: script asks the script's --check (rc package = not installed)" {
    fixture
    pkg_status brave-browser config-files
    BLE_PROFILE=desktop ble 'registry_load; mod_installed 2'
    [ "$status" -eq 1 ]
}

@test "mod_installed: a '-' check always answers no" {
    fixture
    BLE_PROFILE=desktop ble 'registry_load; mod_installed 3'
    [ "$status" -eq 1 ]
}

@test "mod_can_uninstall: yes with an --uninstall script, no without a script" {
    fixture
    BLE_PROFILE=desktop ble 'registry_load; mod_can_uninstall 2'
    [ "$status" -eq 0 ]
    BLE_PROFILE=desktop ble 'registry_load; mod_can_uninstall 3'
    [ "$status" -eq 1 ]
}

# ── the real modules.conf ────────────────────────────────────────────────────

@test "modules.conf: every line has 6 fields and a known tier" {
    run awk -F'|' '!/^#/ && NF && (NF != 6 || $1 !~ /^(necessary|core|secondary)$/) {print NR": "$0}' "$REPO/modules.conf"
    [ -z "$output" ]
}

@test "modules.conf: ids are unique" {
    run bash -c "grep -v '^#' '$REPO/modules.conf' | awk -F'|' 'NF {print \$2}' | sort | uniq -d"
    [ -z "$output" ]
}

@test "modules.conf: every run: script exists" {
    local missing=()
    while read -r s; do
        [[ -f "$REPO/$s" ]] || missing+=("$s")
    done < <(grep -o 'run:[^+|]*' "$REPO/modules.conf" | cut -d: -f2)
    [ ${#missing[@]} -eq 0 ] || { echo "missing: ${missing[*]}"; false; }
}

@test "modules.conf: every tool: is a name in tools.conf" {
    local missing=()
    while read -r t; do
        grep -q "^$t|" "$REPO/tools.conf" || missing+=("$t")
    done < <(grep -o 'tool:[^+|]*' "$REPO/modules.conf" | cut -d: -f2)
    [ ${#missing[@]} -eq 0 ] || { echo "missing: ${missing[*]}"; false; }
}

@test "modules.conf: every secondary app can be uninstalled by setup.sh" {
    BLE_PROFILE=desktop ble 'registry_load
        while read -r i; do mod_can_uninstall "$i" || echo "no --uninstall: ${M_ID[$i]}"; done < <(mod_indices secondary)'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
