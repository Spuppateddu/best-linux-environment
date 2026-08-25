#!/usr/bin/env bash
# Powers the machine off once nobody is using it. How long it waits depends on
# what was last happening; every rule is spelled out in /etc/idle-poweroff.conf.

usage() {
    cat <<'EOF'
idle-poweroff — powers the machine off once nobody is using it.

Waits 1 h at an unlocked desktop, 10 min with the screen locked or no screen at
all. Never while an ssh client is connected, media is playing, a coding agent or
a tmux job is printing, or the load is high — nor for 10 min after the last ssh
client left. Warns first, then acts.

Usage: idle-poweroff [--status|--dry-run]   Settings: /etc/idle-poweroff.conf
EOF
}

# Not `set -e`: a machine we cannot measure must be left alone, not powered off.
set -uo pipefail

# ── Defaults, overridable per machine in /etc/idle-poweroff.conf ─────────────
ENABLED=true
IDLE_MINUTES=60
LOCKED_MINUTES=10
# No screen at all — a headless box, or one whose monitor never logged anybody
# in. Nobody can be sitting at it, so it need not wait the full hour.
HEADLESS_MINUTES=10
WARN_SECONDS=120
# Never this soon after boot. A Wake-on-LAN or post-blackout wake that powered
# off again before you connected would leave a machine you cannot reach.
MIN_UPTIME_MINUTES=15
# Absolute, not per-core: an idle Linux box sits near 0.00 whatever its cores.
MAX_LOAD=0.5
LOCKERS="i3lock swaylock xsecurelock slock xtrlock"
# Keep true on anything reached over the network, or a headless box powers off
# underneath an ssh session that is merely quiet.
BLOCK_ON_LOGIN_SESSIONS=true
# A connected ssh client blocks the poweroff outright, however quiet it is.
BLOCK_ON_SSH=true
# And for this long after the last one closed, so `exit` in an ssh shell does
# not drop the machine two minutes later. 0 turns the grace period off.
SSH_GRACE_MINUTES=10
# Ports to look for ssh connections on, used only when the sshd listener itself
# cannot be read out of `ss` (no process column, or sshd started elsewhere).
SSH_PORTS=22
# A film, a video call or music blocks the poweroff for as long as it plays.
BLOCK_ON_MEDIA=true
# So does a coding agent. Load average cannot see one: an agent waiting on its
# API sits at 0.00 for minutes at a time and still must not be interrupted.
BLOCK_ON_AGENT=true
AGENTS="claude opencode codex aider crush goose"
# An agent silent this long is waiting for YOU, not working, so it stops
# holding the machine up. 0 turns the expiry off; any agent then blocks.
AGENT_SILENT_MINUTES=20
# And so does tmux or screen — attached, or with a pane running something that
# is not just a shell prompt waiting for you.
BLOCK_ON_MUX=true
# Same idea for a tmux pane: a job that is working prints something. 0 turns the
# expiry off, so any non-shell pane blocks for ever.
MUX_SILENT_MINUTES=20
# Pane commands that mean "an idle prompt", not "a job you left running".
MUX_IDLE_SHELLS="bash zsh sh fish dash ksh tmux screen"

CONF=/etc/idle-poweroff.conf
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"

# /run is a tmpfs: the headless counter restarts at boot and `b-idle off` cannot
# outlive a reboot. Both are deliberate.
STATE_DIR=/run/idle-poweroff
IDLE_SINCE="$STATE_DIR/idle-since"
SSH_LAST="$STATE_DIR/ssh-last"
WARNED="$STATE_DIR/warned"
DISABLED="$STATE_DIR/disabled"

MODE=act
case "${1:-}" in
    "")         ;;
    --status)   MODE=status ;;
    --dry-run)  MODE=dry ;;
    -h|--help)  usage; exit 0 ;;
    *) printf 'idle-poweroff: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

IDLE_SECS=$(( IDLE_MINUTES * 60 ))
LOCKED_SECS=$(( LOCKED_MINUTES * 60 ))
SSH_GRACE_SECS=$(( SSH_GRACE_MINUTES * 60 ))
HEADLESS_SECS=$(( HEADLESS_MINUTES * 60 ))
MIN_UPTIME_SECS=$(( MIN_UPTIME_MINUTES * 60 ))
AGENT_SILENT_SECS=$(( AGENT_SILENT_MINUTES * 60 ))
MUX_SILENT_SECS=$(( MUX_SILENT_MINUTES * 60 ))
NOW=$(date +%s)
UPTIME_SECS=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
# An unreadable /proc/uptime must not hand out a free pass forever, so fall back
# to "old enough" and let the real checks decide.
case "$UPTIME_SECS" in ''|*[!0-9]*) UPTIME_SECS=$MIN_UPTIME_SECS ;; esac

has_cmd() { command -v "$1" >/dev/null 2>&1; }
# Journal under the timer, stderr for a human running --status by hand.
log() {
    if [ "$MODE" = act ]; then logger -t idle-poweroff -- "$*"
    else printf '%s\n' "$*" >&2
    fi
}
# Write NOW into a state file, or nothing. Only root can write there, and bash
# prints redirection errors itself, so 2>/dev/null on the printf never helps.
stamp() {
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    [ -w "$STATE_DIR" ] || return 0
    printf '%s\n' "$NOW" > "$1" 2>/dev/null || true
}
human() {
    local s=$1
    if [ "$s" -ge 3600 ]; then printf '%dh %02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
    else printf '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
    fi
}

# ── Probes ───────────────────────────────────────────────────────────────────

# Root-only, and the one reliable source of a session's DISPLAY and XAUTHORITY:
# loginctl's Display is often empty and the greeter's xauth path varies by distro.
environ_of() {
    local pid=$1 var=$2 line
    [ -r "/proc/$pid/environ" ] || return 1
    while IFS= read -r -d '' line; do
        case "$line" in "$var="*) printf '%s\n' "${line#*=}"; return 0 ;; esac
    done < "/proc/$pid/environ"
    return 1
}

# Only `block` mode vetoes; unattended-upgrades holds a permanent `delay` one.
# Both ends of the table are free text, so match WHAT by its fixed vocabulary.
inhibited_for() {
    has_cmd systemd-inhibit || return 1
    systemd-inhibit --list 2>/dev/null | awk -v what="$1" '
        $NF == "block" {
            for (i = 1; i < NF; i++)
                if ($i ~ /^[a-z-]+(:[a-z-]+)*$/ && $i ~ ("(^|:)" what "(:|$)")) found = 1
        }
        END { exit !found }'
}
shutdown_inhibited() { inhibited_for shutdown; }
# What mpv, VLC and a browser playing fullscreen video take out while they play.
idle_inhibited()     { inhibited_for idle; }

# awk, because the shell cannot compare floats.
load_high() {
    local load1
    load1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null) || return 1
    awk -v l="$load1" -v m="$MAX_LOAD" 'BEGIN { exit !(l > m) }'
}

# Seconds since the least-idle tty/ssh login last wrote to its terminal — the
# mtime of the tty device, which is exactly what `w` prints as IDLE.
login_idle() {
    [ "$BLOCK_ON_LOGIN_SESSIONS" = true ] || return 1
    has_cmd who || return 1
    local tty mtime idle min=
    while read -r _ tty _; do
        # X sessions appear in utmp as `:0`, which is not a device node.
        case "$tty" in ""|:*) continue ;; esac
        [ -c "/dev/$tty" ] || continue
        mtime=$(stat -c %Y "/dev/$tty" 2>/dev/null) || continue
        idle=$(( NOW - mtime ))
        [ "$idle" -lt 0 ] && idle=0
        if [ -z "$min" ] || [ "$idle" -lt "$min" ]; then min=$idle; fi
    done < <(who 2>/dev/null)
    [ -n "$min" ] || return 1
    printf '%s\n' "$min"
}

# Someone connected over ssh, whatever they are doing. Never expires: scp, port
# forwards and remote editors touch no tty, and a quiet shell is still in use.
ssh_connected() {
    [ "$BLOCK_ON_SSH" = true ] || return 1
    local sid user host ports port peer

    # logind knows every session sshd opened through PAM, tty or not.
    if has_cmd loginctl; then
        while read -r sid _; do
            [ -n "$sid" ] || continue
            [ "$(loginctl show-session "$sid" -p Remote --value 2>/dev/null)" = yes ] \
                || continue
            user=$(loginctl show-session "$sid" -p Name --value 2>/dev/null)
            host=$(loginctl show-session "$sid" -p RemoteHost --value 2>/dev/null)
            printf '%s@%s, session %s\n' "${user:-?}" "${host:-remote}" "$sid"
            return 0
        done < <(loginctl list-sessions --no-legend 2>/dev/null)
    fi

    # And the sockets themselves, for connections that open no session at all:
    # `ssh -N` port forwards, and sshd built without PAM.
    has_cmd ss || return 1
    # As root the process column names the listener, so any port is found.
    # `sport` is the LOCAL port: matches clients coming in, never going out.
    ports=$(ss -H -tlnp 2>/dev/null | awk '/sshd/ { n = split($4, a, ":"); print a[n] }' | sort -u)
    [ -n "$ports" ] || ports=$SSH_PORTS
    for port in $ports; do
        peer=$(ss -H -tn state established "sport = :$port" 2>/dev/null | awk 'NR == 1 { print $4 }')
        if [ -n "$peer" ]; then
            printf 'from %s on port %s\n' "$peer" "$port"
            return 0
        fi
    done
    return 1
}

# Every logged-in human, as "user uid" lines, each one once. A person with a
# desktop AND an ssh shell is still one person to ask about audio or tmux.
each_user() {
    local sid user uid
    has_cmd loginctl || return 0
    while read -r sid _; do
        [ -n "$sid" ] || continue
        [ "$(loginctl show-session "$sid" -p Class --value 2>/dev/null)" = user ] || continue
        user=$(loginctl show-session "$sid" -p Name --value 2>/dev/null)
        uid=$(loginctl show-session "$sid" -p User --value 2>/dev/null)
        [ -n "$user" ] && [ -n "$uid" ] && printf '%s %s\n' "$user" "$uid"
    done < <(loginctl list-sessions --no-legend 2>/dev/null) | sort -u
}

# Run something inside a user's own session: their PipeWire socket and tmux
# server live under /run/user/<uid>, so root has to become them first.
run_as_user() {
    local user=$1 uid=$2
    shift 2
    if [ "$(id -u)" = "$uid" ]; then
        env XDG_RUNTIME_DIR="/run/user/$uid" "$@" 2>/dev/null
        return
    fi
    has_cmd runuser || return 1
    # runuser resolves through getpwnam and rejects sudo's `#1000` spelling.
    runuser -u "$user" -- env \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        "$@" 2>/dev/null
}

# Seconds since anything was PRINTED on a terminal — the kernel stamps a pty's
# mtime on write. Beware: a program redrawing a status line is never silent.
tty_silent_secs() {
    local tty=$1 mtime secs
    case "$tty" in ''|'?'|'-') return 1 ;; esac
    case "$tty" in /dev/*) ;; *) tty="/dev/$tty" ;; esac
    [ -c "$tty" ] || return 1
    mtime=$(stat -c %Y "$tty" 2>/dev/null) || return 1
    secs=$(( NOW - mtime ))
    [ "$secs" -lt 0 ] && secs=0
    printf '%s\n' "$secs"
}

# A film, a call, music. A sink reads RUNNING only while something feeds it, so
# this needs no list of players; a muted one is caught by its idle inhibitor.
media_playing() {
    [ "$BLOCK_ON_MEDIA" = true ] || return 1
    local user uid sinks
    if has_cmd pactl; then
        while read -r user uid; do
            [ -n "$user" ] || continue
            sinks=$(run_as_user "$user" "$uid" pactl list short sinks) || sinks=""
            if printf '%s\n' "$sinks" | awk '$NF == "RUNNING" { f = 1 } END { exit !f }'; then
                printf 'audio is playing on %s\n' "$user"
                return 0
            fi
        done < <(each_user)
    fi
    if idle_inhibited; then
        printf 'a player is holding an idle inhibitor\n'
        return 0
    fi
    return 1
}

# A coding agent at work — the one thing MAX_LOAD cannot catch, since an agent
# blocked on an HTTP response uses no CPU at all for minutes at a time.
agent_running() {
    [ "$BLOCK_ON_AGENT" = true ] || return 1
    local name pid tty silent
    for name in $AGENTS; do
        # -x so `claude` matches the agent and not `claude-notes.md` in an editor.
        while read -r pid; do
            [ -n "$pid" ] || continue
            if [ "$AGENT_SILENT_SECS" -le 0 ]; then
                printf '%s is running\n' "$name"
                return 0
            fi
            tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
            if ! silent=$(tty_silent_secs "$tty"); then
                # Nothing to watch — output piped to a file, or a service. We
                # cannot tell working from parked, so we leave it alone.
                printf '%s is running with no terminal to watch\n' "$name"
                return 0
            fi
            if [ "$silent" -lt "$AGENT_SILENT_SECS" ]; then
                printf '%s printed something %s ago\n' "$name" "$(human "$silent")"
                return 0
            fi
        done < <(pgrep -x "$name" 2>/dev/null)
    done
    return 1
}

# A tmux pane running something other than a shell means a job was left there.
# No "attached" rule: ssh and the X idle timer already cover a present human.
mux_active() {
    [ "$BLOCK_ON_MUX" = true ] || return 1
    local user uid panes sname ptty pcmd silent sessions
    while read -r user uid; do
        [ -n "$user" ] || continue
        if has_cmd tmux; then
            panes=$(run_as_user "$user" "$uid" tmux list-panes -a \
                -F '#{session_name} #{pane_tty} #{pane_current_command}') || panes=""
            while read -r sname ptty pcmd; do
                [ -n "$pcmd" ] || continue
                # An idle prompt is a window you forgot, not work in progress.
                case " $MUX_IDLE_SHELLS " in *" $pcmd "*) continue ;; esac
                if [ "$MUX_SILENT_SECS" -gt 0 ]; then
                    silent=$(tty_silent_secs "$ptty") || silent=0
                    [ "$silent" -lt "$MUX_SILENT_SECS" ] || continue
                fi
                printf 'tmux session %s is running %s (%s)\n' "$sname" "$pcmd" "$user"
                return 0
            done <<EOT
$panes
EOT
        fi
        if has_cmd screen; then
            # screen reports no window ttys, so attached is all we can see.
            # screen -ls exits 1 when it lists sessions; its status says nothing.
            sessions=$(run_as_user "$user" "$uid" screen -ls) || true
            case "$sessions" in
                *"(Attached)"*) printf 'a screen session is attached (%s)\n' "$user"; return 0 ;;
            esac
        fi
    done < <(each_user)
    return 1
}

# `pgrep -o` takes the OLDEST match, so a respawned child still reports when the
# screen actually went dark.
lock_idle() {
    local name pid secs
    for name in $LOCKERS; do
        pid=$(pgrep -o -x "$name" 2>/dev/null) || continue
        secs=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ') || continue
        [ -n "$secs" ] || continue
        printf '%s\n' "$secs"
        return 0
    done
    return 1
}

# X's own idle timer, in seconds. As root any Xauthority is readable, so the
# greeter's display answers as readily as a logged-in user's.
x_idle() {
    local sid=$1 leader=$2 display xauth ms home user
    has_cmd xprintidle || return 1
    display=$(environ_of "$leader" DISPLAY) \
        || display=$(loginctl show-session "$sid" -p Display --value 2>/dev/null)
    [ -n "$display" ] || return 1
    xauth=$(environ_of "$leader" XAUTHORITY) || xauth=""
    if [ -z "$xauth" ]; then
        user=$(loginctl show-session "$sid" -p Name --value 2>/dev/null)
        home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6)
        [ -n "$home" ] && xauth="$home/.Xauthority"
    fi
    [ -n "$xauth" ] && [ -r "$xauth" ] || return 1
    ms=$(DISPLAY="$display" XAUTHORITY="$xauth" xprintidle 2>/dev/null) || return 1
    case "$ms" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' $(( ms / 1000 ))
}

# ── Collect the checks ───────────────────────────────────────────────────────
# "idle:limit:description" — every check must pass its own limit.
CHECKS=()
BLOCKED=""
GFX_FOUND=false

add_check() { CHECKS+=("$1:$2:$3"); }

if [ "$ENABLED" != true ]; then
    BLOCKED="disabled in $CONF"
elif [ -e "$DISABLED" ]; then
    BLOCKED="disabled until reboot (b-idle off)"
elif [ "$UPTIME_SECS" -lt "$MIN_UPTIME_SECS" ]; then
    BLOCKED="up for only $(human "$UPTIME_SECS") — the first $(human "$MIN_UPTIME_SECS") after a boot are always granted"
elif load_high; then
    BLOCKED="load average $(cut -d' ' -f1 /proc/loadavg) is above $MAX_LOAD"
elif shutdown_inhibited; then
    BLOCKED="a systemd block inhibitor is holding shutdown"
elif ssh_peer=$(ssh_connected); then
    BLOCKED="an ssh client is connected ($ssh_peer)"
    # Stamped on every tick that sees ssh, so the grace period below is counted
    # from the last moment somebody was really connected.
    stamp "$SSH_LAST"
elif media=$(media_playing); then
    BLOCKED="media is playing ($media)"
elif agent=$(agent_running); then
    BLOCKED="a coding agent is working ($agent)"
elif mux=$(mux_active); then
    BLOCKED="a terminal session is in use ($mux)"
fi

if [ -z "$BLOCKED" ]; then
    while read -r sid _; do
        [ -n "$sid" ] || continue
        [ "$(loginctl show-session "$sid" -p Active --value 2>/dev/null)" = yes ] || continue
        class=$(loginctl show-session "$sid" -p Class --value 2>/dev/null)
        type=$(loginctl show-session "$sid" -p Type --value 2>/dev/null)
        # `manager` is the per-user systemd instance, not a screen someone sits at.
        case "$class" in user|greeter) ;; *) continue ;; esac
        case "$type" in x11|wayland|mir) ;; *) continue ;; esac
        GFX_FOUND=true
        leader=$(loginctl show-session "$sid" -p Leader --value 2>/dev/null)

        if locked=$(lock_idle); then
            # Locking is the human saying they left, so no need to wait the hour.
            add_check "$locked" "$LOCKED_SECS" "screen locked (session $sid)"
        elif idle=$(x_idle "$sid" "${leader:-0}"); then
            add_check "$idle" "$IDLE_SECS" "$class session $sid idle"
        else
            # Wayland, or an unreachable Xauthority. Powering off a desktop we
            # cannot see is the one mistake here that cannot be undone.
            BLOCKED="cannot read the idle time of $class session $sid — assuming it is in use"
            break
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
fi

if [ -z "$BLOCKED" ] && [ "$GFX_FOUND" = false ]; then
    # Headless: nothing to interrogate, so count from the first quiet check —
    # after a Wake-on-LAN or post-blackout boot that is the first check at all.
    [ -f "$IDLE_SINCE" ] || stamp "$IDLE_SINCE"
    since=$(cat "$IDLE_SINCE" 2>/dev/null)
    case "$since" in ''|*[!0-9]*) since=$NOW ;; esac
    add_check "$(( NOW - since ))" "$HEADLESS_SECS" "no graphical session since"
fi

if [ -z "$BLOCKED" ] && lidle=$(login_idle); then
    add_check "$lidle" "$IDLE_SECS" "tty/ssh login last active"
fi

# Nothing connected now, but something was. X idle time ignores an ssh logout,
# so without this grace the machine dies minutes after you type `exit`.
if [ -z "$BLOCKED" ] && [ -f "$SSH_LAST" ]; then
    ssh_last=$(cat "$SSH_LAST" 2>/dev/null)
    case "$ssh_last" in ''|*[!0-9]*) ssh_last=$NOW ;; esac
    add_check "$(( NOW - ssh_last ))" "$SSH_GRACE_SECS" "last ssh connection closed"
fi

# ── Decide ───────────────────────────────────────────────────────────────────
IDLE_ENOUGH=true
REASON=""
if [ -n "$BLOCKED" ]; then
    IDLE_ENOUGH=false
    REASON="$BLOCKED"
else
    for check in "${CHECKS[@]}"; do
        idle=${check%%:*}; rest=${check#*:}
        limit=${rest%%:*}; desc=${rest#*:}
        if [ "$idle" -lt "$limit" ]; then
            IDLE_ENOUGH=false
            REASON="$desc $(human "$idle") of $(human "$limit")"
            break
        fi
    done
fi

if [ "$MODE" = status ]; then
    if [ "$IDLE_ENOUGH" = true ]; then
        printf 'idle-poweroff: idle past every limit — would power off.\n'
    else
        printf 'idle-poweroff: in use — %s\n' "$REASON"
    fi
    for check in "${CHECKS[@]}"; do
        idle=${check%%:*}; rest=${check#*:}
        limit=${rest%%:*}; desc=${rest#*:}
        printf '  %-42s %8s / %s\n' "$desc" "$(human "$idle")" "$(human "$limit")"
    done
    [ -e "$WARNED" ] && printf '  warning sent, powering off shortly\n'
    exit 0
fi

# ── Act ──────────────────────────────────────────────────────────────────────
if [ "$IDLE_ENOUGH" != true ]; then
    # Drop both bits of state, so the next idle spell is timed from scratch.
    if [ -e "$WARNED" ]; then
        log "activity resumed ($REASON) — poweroff cancelled"
        rm -f "$WARNED"
    fi
    rm -f "$IDLE_SINCE"
    exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null

# Best effort throughout: a failed notification must not stop the poweroff, or a
# machine with no desktop would never turn off at all.
warn_everybody() {
    local msg="This machine has been idle and will power off in $(human "$WARN_SECONDS"). Move the mouse or press a key to cancel."
    has_cmd wall && printf '%s\n' "$msg" | wall -n 2>/dev/null
    has_cmd notify-send && has_cmd runuser || return 0
    local sid uid user leader bus display xauth
    while read -r sid _; do
        [ -n "$sid" ] || continue
        # A greeter has no notification daemon and nobody to notify.
        [ "$(loginctl show-session "$sid" -p Class --value 2>/dev/null)" = user ] || continue
        # runuser resolves through getpwnam and rejects sudo's `#1000` spelling.
        user=$(loginctl show-session "$sid" -p Name --value 2>/dev/null)
        uid=$(loginctl show-session "$sid" -p User --value 2>/dev/null)
        leader=$(loginctl show-session "$sid" -p Leader --value 2>/dev/null)
        [ -n "$user" ] && [ -n "$leader" ] || continue
        display=$(environ_of "$leader" DISPLAY) \
            || display=$(loginctl show-session "$sid" -p Display --value 2>/dev/null)
        [ -n "$display" ] || display=":0"
        xauth=$(environ_of "$leader" XAUTHORITY) || xauth="/home/$user/.Xauthority"
        # The per-user bus is at a fixed path, so the fallback is as good.
        bus=$(environ_of "$leader" DBUS_SESSION_BUS_ADDRESS) \
            || bus="unix:path=/run/user/${uid:-0}/bus"
        runuser -u "$user" -- env \
            DISPLAY="$display" XAUTHORITY="$xauth" \
            DBUS_SESSION_BUS_ADDRESS="$bus" \
            notify-send -u critical -t "$(( WARN_SECONDS * 1000 ))" \
                "Powering off" "$msg" 2>/dev/null
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    return 0
}

if [ ! -e "$WARNED" ]; then
    log "idle past every limit — warning, then powering off in ${WARN_SECONDS}s"
    printf '%s\n' "$NOW" > "$WARNED" 2>/dev/null
    [ "$MODE" = dry ] || warn_everybody
    exit 0
fi

warned_at=$(cat "$WARNED" 2>/dev/null)
case "$warned_at" in ''|*[!0-9]*) warned_at=$NOW ;; esac
if [ $(( NOW - warned_at )) -lt "$WARN_SECONDS" ]; then
    exit 0
fi

if [ "$MODE" = dry ]; then
    printf 'idle-poweroff: dry run — would power off now.\n'
    exit 0
fi

log "still idle after the warning — powering off"
rm -f "$WARNED" "$IDLE_SINCE"
systemctl poweroff
