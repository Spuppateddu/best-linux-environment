#!/usr/bin/env bash
# settings.local + aliases.local into one override file per surface — the file
# each config reads LAST, so the config repos keep their own defaults and stay
# clean. Same shape as basic/99-font-sizes.sh. See README § settings.local.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Settings (settings.local)"
# After the title, so what settings.local says about a typo of yours reads as
# part of this section rather than as a stray line above it.
source "$BLE_ROOT/lib/settings.sh"

# Belt and braces: basic/05-defaults.sh seeds these in a normal run, but this
# script is also reachable on its own, and it cannot write a colour back into a
# file that is not there.
settings_seed

if [[ -r "$BLE_SETTINGS_LOCAL" ]]; then
    step "Reading ${BLE_SETTINGS_LOCAL/#$HOME/\~}"
else
    skip "No settings.local — every surface keeps what its own repo ships."
fi

# hooked FILE NEEDLE  — true when the config repo's own file still names the
# override we are about to write. Warned about rather than fixed: that file
# belongs to the other repo, and one owner per file is why any of this works.
hooked() {
    [[ -f "$1" ]] || return 1
    grep -Fq "$2" "$1" && return 0
    warn "${1/#$HOME/\~} does not load $2 — pull that repo, the hook lives there."
    return 1
}

# ── 1. the colours, rolled once ──────────────────────────────────────────────
# Rolled here rather than in the parser, because rolling means WRITING: every
# colour goes back into settings.local, and a colour that changed on you at
# every boot would be a bug rather than a feature.
#
# "Roll again" from ./setup.sh: every colour goes, pinned ones too. Under
# --dry-run only the values are forgotten, so the preview shows the roll.
if [[ "${BLE_ROLL_COLORS:-false}" == true ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        for k in "${BLE_COLOR_KEYS[@]}"; do printf -v "$k" '%s' ""; done
    else
        settings_forget_colors
    fi
    step "Rolling every colour again, as asked."
fi

# Which ones already had a value, taken BEFORE the roll: only a colour that was
# actually rolled is written back, so one you pinned by hand stays where you put
# it. Read after settings_load, so a value it threw out counts as missing.
declare -A HAD=()
for k in "${BLE_COLOR_KEYS[@]}"; do HAD[$k]="${!k}"; done

# The two pairs — never equal, never the same hue. The cursor stands alone.
roll_color_pair BLE_PROMPT_COLOR_USER BLE_PROMPT_COLOR_PATH
roll_color_pair BLE_I3_BORDER_COLOR BLE_I3_UNFOCUSED_COLOR
roll_color BLE_CURSOR_COLOR

ROLLED=()
for k in "${BLE_COLOR_KEYS[@]}"; do
    [[ -z "${HAD[$k]}" ]] && ROLLED+=("$k")
done

if [[ ${#ROLLED[@]} -eq 0 ]]; then
    step "Colours: all ${#BLE_COLOR_KEYS[@]} are yours, from settings.local."
    for k in "${BLE_COLOR_KEYS[@]}"; do
        printf '%s    %s (%s) — %s%s\n' "$C_DIM" "${!k}" "$(color_name "${!k}")" "${BLE_COLOR_WHAT[$k]}" "$C_OFF"
    done
elif [[ "$DRY_RUN" == true ]]; then
    # Before the "no file" arm below: under --dry-run the seed above only
    # printed, so the file is missing for that reason and not for a real one.
    for k in "${ROLLED[@]}"; do
        printf '%s  would roll:%s %s=%s (%s) → %s\n' "$C_DIM" "$C_OFF" \
            "$k" "${!k}" "$(color_name "${!k}")" "${BLE_SETTINGS_LOCAL/#$HOME/\~}"
    done
elif [[ ! -f "$BLE_SETTINGS_LOCAL" ]]; then
    warn "No settings.local to write the rolled colours into — they change on the next run."
else
    # Appended rather than edited in place: the parser takes the LAST value of a
    # key, so the new line wins over a bad one above it without this having to
    # rewrite a file that is yours.
    {
        printf '\n# Rolled by best-linux-environment on %s, once. Delete a line below to get a\n' "$(date '+%F')"
        printf '# new colour for that one surface; edit it to keep the colour for good (0-255;\n'
        printf '# the two prompt colours must differ, and so must the two i3 ones).\n'
        for k in "${ROLLED[@]}"; do
            printf '%s=%s   # %s — %s\n' "$k" "${!k}" "$(color_name "${!k}")" "${BLE_COLOR_WHAT[$k]}"
        done
    } >> "$BLE_SETTINGS_LOCAL"
    for k in "${ROLLED[@]}"; do
        ok "Rolled ${BLE_COLOR_WHAT[$k]}: $(color_name "${!k}")."
    done
    ok "Kept in ${BLE_SETTINGS_LOCAL/#$HOME/\~} — they will not change again."
fi

U256="$BLE_PROMPT_COLOR_USER"; P256="$BLE_PROMPT_COLOR_PATH"
# Computed once, unconditionally: section 4 wants it only when Alacritty is
# cloned, but the shell blocks below want it on every machine, headless ones
# included — that's what lets a machine's own colour ride an SSH session.
CURSOR_HEX="$(color_hex "$BLE_CURSOR_COLOR")"
U8="$(color_fallback8 "$U256")"; P8="$(color_fallback8 "$P256")"
UZ="$(color_zsh_name "$U8")";    PZ="$(color_zsh_name "$P8")"

# ── 2. the shared aliases ────────────────────────────────────────────────────
# Checked before it is copied anywhere: this file ends up sourced by every new
# shell, and a syntax error in it means no shell on this machine has a prompt.
ALIAS_BODY=""
if [[ -s "$BLE_ALIASES_LOCAL" ]]; then
    if ! bash -n "$BLE_ALIASES_LOCAL" 2>/dev/null; then
        fail "${BLE_ALIASES_LOCAL/#$HOME/\~} has a syntax error — not installing it."
        fail "Every new shell would break. What bash makes of it:"
        bash -n "$BLE_ALIASES_LOCAL" 2>&1 | sed 's/^/    /' >&2 || true
        FAILED_ALIASES=true
    else
        ALIAS_BODY="$(cat "$BLE_ALIASES_LOCAL")"
        step "Shared aliases: $(grep -cE '^[[:space:]]*(alias|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\))' "$BLE_ALIASES_LOCAL" || true) definition(s) from ${BLE_ALIASES_LOCAL/#$HOME/\~}"
    fi
fi

# ── 3. one override file per shell ───────────────────────────────────────────
# Loaded from ~/.<shell>rc, after the line the config repo put there — so this
# is the last word on the prompt, which is the only place it can be: bash sets
# PS1 at the very end of its own rc, and Oh My Zsh's theme sets PROMPT at the
# end of zsh's.
prompt_block_bash() {
    local b; b="$(cat <<'BASH_BLOCK'
# ── prompt ───────────────────────────────────────────────────────────────────
# Stock bash's `user@host:path$`, in the two colours settings.local rolled for
# this machine. \[ \] mark the escapes zero-width, else readline wraps long
# lines early.
if [[ $- == *i* ]]; then
    _ble_colors=$(tput colors 2>/dev/null || echo 0)
    if [ "$_ble_colors" -ge 256 ]; then
        PS1='${debian_chroot:+($debian_chroot)}\[\033[1;38;5;@U256@m\]\u@\h\[\033[00m\]:\[\033[1;38;5;@P256@m\]\w\[\033[00m\]\$ '
    elif [ "$_ble_colors" -ge 8 ]; then
        # No 256-colour palette here: the nearest of the eight ANSI colours.
        PS1='${debian_chroot:+($debian_chroot)}\[\033[01;@U8@m\]\u@\h\[\033[00m\]:\[\033[01;@P8@m\]\w\[\033[00m\]\$ '
    else
        PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
    fi
    unset _ble_colors

    # The window title, which the assignment above dropped.
    case "$TERM" in
        xterm*|rxvt*|alacritty*|tmux*|screen*)
            PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
            ;;
    esac

    # OSC 12: paint the terminal cursor in THIS machine's colour for the length
    # of the SSH session, so you can tell which box you are on by the cursor
    # alone. OSC 112 on exit puts it back to the terminal's own default — which
    # is the local machine's colour, already painted by Alacritty's config —
    # so a box with no best-linux-environment never sends anything and the
    # cursor just stays whatever the local machine set. Nested SSH resets to
    # that same local default rather than the previous hop's colour.
    if [[ -n "$SSH_CLIENT" || -n "$SSH2_CLIENT" ]]; then
        case "$TERM" in
            xterm*|rxvt*|alacritty*|tmux*|screen*)
                printf '\e]12;#@CURSOR_HEX@\a'
                trap 'printf "\e]112\a"' EXIT
                ;;
        esac
    fi
fi
BASH_BLOCK
)"
    b="${b//@U256@/$U256}"; b="${b//@P256@/$P256}"
    b="${b//@U8@/$U8}";     b="${b//@P8@/$P8}"
    b="${b//@CURSOR_HEX@/$CURSOR_HEX}"
    printf '%s\n' "$b"
}

prompt_block_zsh() {
    local b; b="$(cat <<'ZSH_BLOCK'
# ── prompt ───────────────────────────────────────────────────────────────────
# The gnzh prompt this repo's zsh config uses, rebuilt with the two colours
# settings.local rolled for this machine. Same shape, same git and virtualenv
# segments — only %n@%m and %~ change colour. In an anonymous function, the way
# gnzh does it, so none of the locals leak into your shell.
if [[ -o interactive ]]; then
  setopt prompt_subst
  zmodload -i zsh/terminfo 2>/dev/null
  () {
    local pr_user pr_op pr_host uc pc
    if (( ${terminfo[colors]:-0} >= 256 )); then
      uc='@U256@'; pc='@P256@'
    else
      uc='@UZ@'; pc='@PZ@'
    fi

    # root stays red whatever the roll said: that one is a warning, not a style.
    if (( UID != 0 )); then
      pr_user="%F{$uc}%n%f"; pr_op='%f➤ %f'
    else
      pr_user='%F{red}%n%f'; pr_op='%F{red}➤ %f'
    fi
    # And so is "you are not on this machine".
    if [[ -n "$SSH_CLIENT" || -n "$SSH2_CLIENT" ]]; then
      pr_host='%F{red}%M%f'
    else
      pr_host="%F{$uc}%m%f"
    fi

    # Guarded: without Oh My Zsh these functions do not exist, and the prompt
    # would print a command-not-found line every time you press enter.
    local git_branch='' venv_prompt='' ruby_prompt=''
    (( ${+functions[git_prompt_info]} ))        && git_branch='$(git_prompt_info)'
    (( ${+functions[virtualenv_prompt_info]} )) && venv_prompt='$(virtualenv_prompt_info)'
    (( ${+functions[ruby_prompt_info]} ))       && ruby_prompt='$(ruby_prompt_info)'

    # Joined only when there is something to join, or an empty git segment
    # leaves two stray spaces hanging off the end of every prompt line.
    local head="╭─${venv_prompt}${pr_user}%F{cyan}@%f${pr_host} %B%F{$pc}%~%f%b"
    [[ -n "$ruby_prompt" ]] && head="$head ${ruby_prompt}"
    [[ -n "$git_branch" ]]  && head="$head ${git_branch}"

    PROMPT="$head
╰─${pr_op} "
    RPROMPT="%(?..%F{red}%? ↵%f)"
  }

  # OSC 12: paint the terminal cursor in THIS machine's colour for the length
  # of the SSH session, so you can tell which box you are on by the cursor
  # alone. OSC 112 on exit puts it back to the terminal's own default — which
  # is the local machine's colour, already painted by Alacritty's config —
  # so a box with no best-linux-environment never sends anything and the
  # cursor just stays whatever the local machine set. Nested SSH resets to
  # that same local default rather than the previous hop's colour.
  if [[ -n "$SSH_CLIENT" || -n "$SSH2_CLIENT" ]]; then
    case "$TERM" in
      xterm*|rxvt*|alacritty*|tmux*|screen*)
        printf '\e]12;#@CURSOR_HEX@\a'
        trap 'printf "\e]112\a"' EXIT
        ;;
    esac
  fi
fi
ZSH_BLOCK
)"
    b="${b//@U256@/$U256}"; b="${b//@P256@/$P256}"
    b="${b//@UZ@/$UZ}";     b="${b//@PZ@/$PZ}"
    b="${b//@CURSOR_HEX@/$CURSOR_HEX}"
    printf '%s\n' "$b"
}

# shell_file SHELL  — the whole generated file for one shell, on stdout.
shell_file() {
    local shell_name="$1"
    printf '# Written by best-linux-environment — do NOT edit, every run rewrites it.\n'
    printf '# Change it in %s/settings.local and %s/aliases.local instead,\n' \
        "${BLE_ROOT/#$HOME/\~}" "${BLE_ROOT/#$HOME/\~}"
    printf '# then run ./setup.sh (or ./boot.sh, or just reboot).\n'
    printf '#\n'
    if [[ "$shell_name" == zsh ]]; then
        printf '# Loaded LAST, from ~/.zshrc — after Oh My Zsh and its theme, after the config\n'
        printf '# repo, after ~/.zsh/zsh-alias.local. Last means what is here wins.\n'
    else
        printf '# Loaded LAST, from ~/.bashrc — after the config repo set its own prompt,\n'
        printf '# after ~/.bash/bash-alias.local. Last means what is here wins.\n'
    fi
    printf '\n'

    printf '# ── environment (settings.local) ──────────────────────────────────────────────\n'
    if [[ -n "$BLE_EDITOR" ]]; then
        printf 'export EDITOR=%q\n' "$BLE_EDITOR"
        printf 'export VISUAL=%q\n' "$BLE_EDITOR"
    fi
    if [[ -n "$BLE_AGENT_DESK" ]]; then
        printf '# Where $mod+c opens the agent, so you can `cd "$BLE_AGENT_DESK"` too.\n'
        printf 'export BLE_AGENT_DESK=%q\n' "$BLE_AGENT_DESK"
    fi
    [[ -z "$BLE_EDITOR" && -z "$BLE_AGENT_DESK" ]] && \
        printf '# Nothing set in settings.local — nothing exported.\n'
    printf '\n'

    printf '# ── your aliases (aliases.local) ──────────────────────────────────────────────\n'
    if [[ -n "$ALIAS_BODY" ]]; then
        printf '%s\n' "$ALIAS_BODY"
    else
        printf '# aliases.local is empty. Uncomment something in it, or in\n'
        printf '# %s/aliases.local.example, and re-run.\n' "${BLE_ROOT/#$HOME/\~}"
    fi
    printf '\n'

    "prompt_block_$shell_name"
}

# What ~/.i3rc/05-agent.local holds, on stdout.
i3_agent_file() {
    printf '# Written by best-linux-environment — settings.local, BLE_AGENT / BLE_AGENT_DESK.\n'
    printf '# Read by ~/.i3rc/scripts/agent.sh, which $mod+c runs. Named 05- so a value\n'
    printf '# you put in config.local by hand is still read after this and still wins.\n'
    [[ -n "$BLE_AGENT" ]]      && printf 'set $agent %s\n' "$BLE_AGENT"
    [[ -n "$BLE_AGENT_DESK" ]] && printf 'set $agent_desk %s\n' "$BLE_AGENT_DESK"
    return 0
}

# What ~/.i3rc/06-colors.local holds, on stdout: focused and unfocused windows
# in the two rolled colours. Tiling mode greys the unfocused ones back (90- wins).
i3_colors_file() {
    local hex unhex text untext
    hex="#$(color_hex "$BLE_I3_BORDER_COLOR")";      text="#$(color_text_on "$BLE_I3_BORDER_COLOR")"
    unhex="#$(color_hex "$BLE_I3_UNFOCUSED_COLOR")"; untext="#$(color_text_on "$BLE_I3_UNFOCUSED_COLOR")"
    printf '# Written by best-linux-environment — settings.local, BLE_I3_BORDER_COLOR\n'
    printf '# and BLE_I3_UNFOCUSED_COLOR.\n'
    printf '# Do NOT edit: every run rewrites it. Change the colour in\n'
    printf '# %s/settings.local, then re-run.\n' "${BLE_ROOT/#$HOME/\~}"
    printf '#\n'
    printf '# Named 06- so config.local, which i3 reads after it, still wins.\n'
    printf '# Fields: border, background, text, indicator, child_border.\n'
    printf '# The text is the title bar: white on a dark colour, near-black on a\n'
    printf '# light one, so the title always reads whatever number you pick.\n'
    printf 'client.focused          %s %s %s %s %s\n' "$hex" "$hex" "$text" "$hex" "$hex"
    # focused_inactive: the window that would get the keyboard in a container
    # you are not in. Not focused, so it takes the unfocused colour.
    printf 'client.focused_inactive %s %s %s %s %s\n' "$unhex" "$unhex" "$untext" "$unhex" "$unhex"
    printf 'client.unfocused        %s %s %s %s %s\n' "$unhex" "$unhex" "$untext" "$unhex" "$unhex"
    return 0
}

# What ~/.i3rc/00-no-titlebar.local holds, on stdout: config's own 3px border in
# the style that draws no title bar. Its presence is the whole flag.
i3_titlebar_file() {
    printf '# Written by best-linux-environment — settings.local, BLE_I3_TITLEBAR=false.\n'
    printf '# Do NOT edit: every run rewrites it. Set the key to true to get titles back.\n'
    printf '\n'
    printf '# Named 00-no-titlebar: 00-tiling-border.local, 07-, 08- and config.local are\n'
    printf '# read after it, and desktop_mode.sh reads the file itself as the flag.\n'
    printf '\n'
    printf '# pixel, not normal: the same width as config gives, minus the title bar.\n'
    printf 'for_window [class=".*"] border pixel 3\n'
    printf 'default_floating_border pixel 3\n'
    printf 'default_border          pixel 3\n'
    return 0
}

# i3_sweep_titlebar FROM TO  — rules only fire when a window is mapped, so swap
# the style on the open ones too. Width kept, so a per-app 1px is never touched.
i3_sweep_titlebar() {
    local from="$1" to="$2" cmd="" id w
    if ! has_cmd jq; then
        skip "jq not installed — windows already open keep their title bar until reopened."
        return 0
    fi
    while read -r id w; do
        [[ -n "$id" ]] && cmd+="[con_id=$id] border $to $w; "
    done < <(i3-msg -t get_tree 2>/dev/null | jq -r --arg from "$from" '
        def desc: recurse(.nodes[]?, .floating_nodes[]?);
        desc | select(.window != null)
             | select(.border == $from)
             | select(.current_border_width >= 2 and .current_border_width <= 4)
             | "\(.id) \(.current_border_width)"' 2>/dev/null)
    [[ -n "$cmd" ]] || return 0
    i3-msg "${cmd%; }" >/dev/null 2>&1 \
        && ok "Windows already open swapped to 'border $to' too." \
        || warn "Could not swap the border on the windows already open."
}

# The line that loads it, appended once to the rc file. Guarded on the file
# existing, so removing this repo cannot leave you with a shell that errors.
rc_line() {
    printf '[ -f "$HOME/.%s/%s-ble.local" ] && . "$HOME/.%s/%s-ble.local"  # best-linux-environment\n' \
        "$1" "$1" "$1" "$1"
}

# zsh reads $ZDOTDIR/.zshrc when ZDOTDIR is set, and $HOME/.zshrc otherwise —
# wiring the wrong one wires a file nothing loads.
rc_path() {
    case "$1" in
        zsh)  printf '%s/.zshrc' "${ZDOTDIR:-$HOME}" ;;
        bash) printf '%s/.bashrc' "$HOME" ;;
    esac
}

# A broken aliases.local stops the shell files being touched at all, rather than
# being quietly left out of them: the copy already on disk is the last one that
# worked, and keeping it beats stripping every alias off the machine because of
# one missing quote. Fix the file and re-run.
SHELL_DONE=false
if [[ "${FAILED_ALIASES:-false}" == true ]]; then
    warn "Leaving ~/.zsh/zsh-ble.local and ~/.bash/bash-ble.local exactly as they are."
    warn "Fix the quote above and re-run — nothing else on this run is affected."
fi
for shell_name in zsh bash; do
    [[ "${FAILED_ALIASES:-false}" == true ]] && break
    config_dir="$HOME/.$shell_name"
    gen_file="$config_dir/$shell_name-ble.local"
    rc="$(rc_path "$shell_name")"

    # The config repo's own file, not the symlink: no repo, nothing to extend.
    if [[ ! -f "$config_dir/${shell_name}rc" ]]; then
        skip "No $shell_name config wired in (${config_dir/#$HOME/\~}) — nothing to write there."
        continue
    fi
    SHELL_DONE=true

    # A herestring, not a pipe: the right-hand side of a pipe runs in a
    # subshell, and GEN_CHANGED would come back from it unchanged.
    write_gen "$gen_file" <<< "$(shell_file "$shell_name")"

    # A generated zsh file is checked by zsh, when there is one — bash -n would
    # reject the anonymous function and the %F escapes are none of its business.
    if [[ "$DRY_RUN" != true && -f "$gen_file" ]]; then
        if [[ "$shell_name" == zsh ]] && has_cmd zsh; then
            zsh -n "$gen_file" 2>/dev/null || warn "$(basename "$gen_file") does not parse as zsh — open a new shell and check."
        elif [[ "$shell_name" == bash ]]; then
            bash -n "$gen_file" 2>/dev/null || warn "$(basename "$gen_file") does not parse as bash — open a new shell and check."
        fi
    fi

    if [[ -f "$rc" ]]; then
        ensure_line "$rc" "$shell_name-ble\.local" "$(rc_line "$shell_name")"
        [[ "$LINE_ADDED" == true ]] && \
            step "${rc/#$HOME/\~} now loads it last — open a new $shell_name to see the prompt."
    else
        skip "${rc/#$HOME/\~} does not exist — ./setup.sh's $shell_name config writes it."
    fi
done

if [[ "$SHELL_DONE" == false && "${FAILED_ALIASES:-false}" != true ]]; then
    skip "No shell config repo is wired in — run ./setup.sh and pick zsh or bash."
fi

# ── 4. the terminal cursor (Alacritty) ───────────────────────────────────────
# Alacritty merges its imports and the LAST one wins, so this file is listed
# after ~/.cache/alacritty-theme.toml — the file $mod+Shift+t rewrites. That
# ordering is the whole trick: the theme toggle keeps owning the dark/light
# scheme, and the cursor keeps the colour this machine rolled either way.
ALA="$HOME/.alacritty"
if [[ ! -d "$ALA" ]]; then
    skip "${ALA/#$HOME/\~} not cloned yet — no terminal cursor to colour (./setup.sh clones it)."
elif hooked "$ALA/alacritty.toml" "colors.local.toml"; then
    write_gen "$ALA/colors.local.toml" <<EOF
# Written by best-linux-environment — settings.local, BLE_CURSOR_COLOR.
# Do NOT edit: every run rewrites it. Change the colour in
# ${BLE_ROOT/#$HOME/\~}/settings.local, then re-run.
#
# Imported after ~/.cache/alacritty-theme.toml, so \$mod+Shift+t can keep
# swapping dark and light without taking this colour with it.
[colors.cursor]
cursor = '0x$CURSOR_HEX'
# The character the block sits on. Kept dark rather than left to Alacritty's
# default: every colour in the palette is a bright one, so dark always reads.
text = '0x1d2021'
EOF
    # Alacritty watches its own imports and re-reads them, so there is nothing
    # to reload here — the cursor changes colour in the windows already open.
fi

# ── 5. i3: the agent key ($mod+c), the window colours, the title bars ────────
# 05- so it sorts before config.local, which i3's `include ~/.i3rc/*.local`
# reads after it: a value you put in config.local by hand still wins.
I3="$HOME/.i3rc"
I3_GEN="$I3/05-agent.local"
if [[ ! -d "$I3" ]]; then
    skip "${I3/#$HOME/\~} not cloned yet — no \$mod+c to configure (./setup.sh clones it)."
elif ! grep -Fq 'include ~/.i3rc/*.local' "$I3/config" 2>/dev/null; then
    warn "${I3/#$HOME/\~}/config does not include ~/.i3rc/*.local — pull that repo, the hook lives there."
else
    if [[ -n "$BLE_AGENT" || -n "$BLE_AGENT_DESK" ]]; then
        write_gen "$I3_GEN" <<< "$(i3_agent_file)"
        CHANGED_I3="$GEN_CHANGED"
    else
        drop_gen "$I3_GEN" "~/.i3rc/config.local"
        CHANGED_I3="$GEN_CHANGED"
        skip "No BLE_AGENT in settings.local — \$mod+c has no agent to open yet."
        skip "Set one there (BLE_AGENT=claude) rather than in ~/.i3rc/config.local."
    fi

    # The window colours. Always written: the roll above always leaves both
    # i3 keys with a value, so there is no "unset" case to drop.
    write_gen "$I3/06-colors.local" <<< "$(i3_colors_file)"
    [[ "$GEN_CHANGED" == true ]] && CHANGED_I3=true

    # The title bars. The file's presence is the flag, for i3 and for the
    # tiling switch alike — there is no "titles on" file, only its absence.
    if [[ "$BLE_I3_TITLEBAR" == false ]]; then
        write_gen "$I3/00-no-titlebar.local" <<< "$(i3_titlebar_file)"
        hooked "$I3/scripts/desktop_mode.sh" "00-no-titlebar.local" || \
            warn "The tiling desktop will put the title bars back on its next switch."
    else
        drop_gen "$I3/00-no-titlebar.local" "~/.i3rc/config"
    fi
    if [[ "$GEN_CHANGED" == true ]]; then
        CHANGED_I3=true
        SWEEP_TITLEBAR=true
    fi

    # The one thing that silently undoes this file. config.local sorts after it,
    # so a `set $agent` left in there wins and settings.local looks broken.
    if [[ -f "$I3/config.local" ]]; then
        for var in agent agent_desk; do
            grep -Eq "^[[:space:]]*set[[:space:]]+\\\$$var[[:space:]]" "$I3/config.local" || continue
            [[ "$var" == agent && -z "$BLE_AGENT" ]] && continue
            [[ "$var" == agent_desk && -z "$BLE_AGENT_DESK" ]] && continue
            warn "~/.i3rc/config.local also sets \$$var — that one wins, and settings.local's is ignored."
            warn "Delete its 'set \$$var …' line to let settings.local decide."
        done

        # Same trap, for the colours: config.local sorts after 06-colors.local.
        for cls in focused focused_inactive unfocused; do
            grep -Eq "^[[:space:]]*client\.$cls[[:space:]]" "$I3/config.local" || continue
            warn "~/.i3rc/config.local also sets client.$cls — that one wins, and settings.local's colour is ignored."
            warn "Delete its 'client.$cls …' line to let settings.local decide."
        done
    fi

    # Made here as well as by the i3 repo's own setup, so the key works on a
    # machine whose i3 install predates this setting.
    if [[ -n "$BLE_AGENT_DESK" ]]; then
        if [[ -d "$BLE_AGENT_DESK" ]]; then
            skip "${BLE_AGENT_DESK/#$HOME/\~} already exists."
        else
            run mkdir -p "$BLE_AGENT_DESK" && ok "created ${BLE_AGENT_DESK/#$HOME/\~} — where \$mod+c opens." \
                || warn "Could not create $BLE_AGENT_DESK."
        fi
    fi

    # Named but not installed is worth saying now rather than at the keypress.
    if [[ -n "$BLE_AGENT" ]]; then
        agent_bin="${BLE_AGENT%% *}"
        has_cmd "$agent_bin" || have_local_bin "$agent_bin" || \
            warn "BLE_AGENT names '$agent_bin', which is not on PATH — \$mod+c will say so too."
    fi
fi

# ── 6. Firefox: its own title bar ────────────────────────────────────────────
# The repo's install.sh appends user.settings.local.js to user.js, where the
# last pref wins — same trick fonts.local uses next door for the sizes.
FF="$HOME/.firefox"
CHANGED_FIREFOX=false
if [[ ! -d "$FF" ]]; then
    skip "${FF/#$HOME/\~} not cloned yet — no Firefox pref to set (./setup.sh clones it)."
elif hooked "$FF/install.sh" "user.settings.local.js"; then
    if [[ -n "$BLE_FIREFOX_TITLEBAR" ]]; then
        # 1 puts the tabs in the title bar, so Firefox draws none of its own; 0
        # gives it back. i3 draws a title bar of its own either way.
        [[ "$BLE_FIREFOX_TITLEBAR" == true ]] && IN_TITLEBAR=0 || IN_TITLEBAR=1
        write_gen "$FF/user.settings.local.js" <<EOF
// Written by best-linux-environment — settings.local, BLE_FIREFOX_TITLEBAR.
// Do NOT edit: every run rewrites it. Change the key there, then re-run.
user_pref("browser.tabs.inTitlebar", $IN_TITLEBAR);
EOF
    else
        drop_gen "$FF/user.settings.local.js" "~/.firefox/user.js"
    fi
    CHANGED_FIREFOX="$GEN_CHANGED"
fi

# ── 7. git ───────────────────────────────────────────────────────────────────
# Asserted, not seeded: basic/05-defaults.sh sets what is missing and leaves
# your own values alone, but a value in settings.local IS your own value, said
# once for every machine.
if ! has_cmd git; then
    skip "git not installed yet — its settings are applied on the next run."
else
    git_assert() {
        local key="$1" value="$2" current
        [[ -n "$value" ]] || return 0
        current="$(git config --global --get "$key" 2>/dev/null || true)"
        if [[ "$current" == "$value" ]]; then
            skip "git $key already $value."
        elif [[ "$DRY_RUN" == true ]]; then
            printf '%s  would set:%s git config --global %s %s\n' "$C_DIM" "$C_OFF" "$key" "$value"
        else
            git config --global "$key" "$value"
            ok "git $key = $value"
        fi
    }
    git_assert user.name  "$BLE_GIT_NAME"
    git_assert user.email "$BLE_GIT_EMAIL"
    git_assert core.editor "$BLE_EDITOR"
fi

# ── 8. apply it to what is running ───────────────────────────────────────────
[[ "$DRY_RUN" == true ]] && { ok "Settings ready."; exit 0; }

if [[ "${CHANGED_I3:-false}" == true && -n "${DISPLAY:-}" ]] && has_cmd i3-msg \
   && i3-msg -t get_version >/dev/null 2>&1; then
    i3-msg -q reload >/dev/null 2>&1 && ok "i3 reloaded — \$mod+c uses the new settings." \
        || warn "i3 reload failed."
    if [[ "${SWEEP_TITLEBAR:-false}" == true ]]; then
        if [[ "$BLE_I3_TITLEBAR" == false ]]; then
            i3_sweep_titlebar normal pixel
        else
            i3_sweep_titlebar pixel normal
        fi
    fi
fi

# Firefox reads its prefs out of the profile, and only its own install.sh puts
# them there. Re-run for that one repo, and only when the pref actually moved.
if [[ "$CHANGED_FIREFOX" == true && -x "$FF/install.sh" ]]; then
    step "Re-applying the Firefox config, so the new pref reaches the profile"
    bash "$BLE_ROOT/basic/10-tools.sh" firefox || warn "Could not re-apply ~/.firefox."
    warn "Restart Firefox to see it."
fi

# Nothing can push a new prompt into a shell that already exists, so say it
# rather than pretending the run finished the job.
if [[ "$SHELL_DONE" == true ]]; then
    skip "Shells already open keep their old prompt and aliases — open a new one."
fi

[[ "${FAILED_ALIASES:-false}" == true ]] && exit 1
ok "Settings ready."
