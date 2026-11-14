#!/usr/bin/env bash
# Browser clean: every BLE_BROWSER_CLEAN_DAYS days, empty the browsers you ticked
# in ./setup.sh. Source after lib/common.sh. Used by browser-clean/b-browser-clean
# (./boot.sh runs it, and you can by hand) and by setup.sh (which ones are ticked).
#
# Deleted: history, downloads list, cookies (you are logged out of every site),
# cache, site data (local storage, IndexedDB, service worker caches), form history,
# site permissions and zoom, open tabs.
# Kept: passwords, credit cards, addresses, bookmarks, extensions and their
# settings, the browser's own settings (the ones the config repos write).

[[ -n "${_BLE_BROWSER_CLEAN_LOADED:-}" ]] && return 0
_BLE_BROWSER_CLEAN_LOADED=1

# The browsers this repo installs. Order is the order of every list and run.
BC_IDS=(firefox google-chrome brave)
declare -A BC_NAME=([firefox]=Firefox [google-chrome]="Google Chrome" [brave]=Brave)
# The command each one puts on PATH: how we tell it is installed.
declare -A BC_CMD=([firefox]=firefox [google-chrome]=google-chrome-stable [brave]=brave-browser)
# Chromium-family browsers: the profile folder and the cache folder.
declare -A BC_DATA=(
    [google-chrome]="$HOME/.config/google-chrome"
    [brave]="$HOME/.config/BraveSoftware/Brave-Browser"
)
declare -A BC_CACHE=(
    [google-chrome]="$HOME/.cache/google-chrome"
    [brave]="$HOME/.cache/BraveSoftware/Brave-Browser"
)

# One `ID EPOCH` line per ticked browser: EPOCH is its last clean, or the moment
# it was ticked — so ticking one starts its timer and deletes nothing that day.
BC_STATE="${BC_STATE:-$BLE_STATE_DIR/browser-clean}"
BC_DEFAULT_DAYS=7

bc_days() { printf '%s' "${BLE_BROWSER_CLEAN_DAYS:-$BC_DEFAULT_DAYS}"; }
bc_now() { printf '%s' "${BC_NOW:-$(date +%s)}"; }

bc_known() {
    local id
    for id in "${BC_IDS[@]}"; do [[ "$id" == "$1" ]] && return 0; done
    return 1
}
bc_installed() { has_cmd "${BC_CMD[$1]}"; }

bc_ticked() { [[ -f "$BC_STATE" ]] && awk -v id="$1" '$1 == id { f = 1 } END { exit !f }' "$BC_STATE"; }
bc_list()   { [[ -f "$BC_STATE" ]] && awk 'NF { print $1 }' "$BC_STATE" || true; }
bc_last()   { [[ -f "$BC_STATE" ]] && awk -v id="$1" '$1 == id { print $2 }' "$BC_STATE" || true; }

# _bc_write  — replace the state file with stdin, through a temp file, so a
# crash halfway never leaves half a list (which would untick a browser).
_bc_write() {
    [[ "$DRY_RUN" == true ]] && { cat >/dev/null; return 0; }
    mkdir -p "$(dirname "$BC_STATE")"
    cat > "$BC_STATE.$$" && mv -f "$BC_STATE.$$" "$BC_STATE"
}

# bc_stamp ID  — ID was just cleaned: its timer starts again from now.
bc_stamp() {
    local id="$1" now; now="$(bc_now)"
    { [[ -f "$BC_STATE" ]] && awk -v id="$id" '$1 != id' "$BC_STATE"; printf '%s %s\n' "$id" "$now"; } | _bc_write
}

# bc_set_ticked ID…  — exactly these are ticked. One already ticked keeps its
# date; a new one gets today's, so its first clean is BLE_BROWSER_CLEAN_DAYS away.
bc_set_ticked() {
    local id last now; now="$(bc_now)"
    for id in "$@"; do
        last="$(bc_last "$id")"
        printf '%s %s\n' "$id" "${last:-$now}"
    done | _bc_write
}

# bc_due_in ID  — seconds until ID is due (0 or less: due now).
bc_due_in() {
    local last; last="$(bc_last "$1")"
    [[ "$last" =~ ^[0-9]+$ ]] || last="$(bc_now)"
    printf '%s' $(( last + $(bc_days) * 86400 - $(bc_now) ))
}

# bc_ago SECONDS  — "3 days", "5 hours", "a few minutes", for the status lines.
bc_ago() {
    local s="$1"
    (( s < 0 )) && s=$(( -s ))
    if (( s >= 172800 )); then printf '%s days' $(( s / 86400 ))
    elif (( s >= 86400 )); then printf '1 day'
    elif (( s >= 7200 )); then printf '%s hours' $(( s / 3600 ))
    elif (( s >= 3600 )); then printf '1 hour'
    else printf 'a few minutes'
    fi
}

# ── where the profiles are ───────────────────────────────────────────────────
# Firefox: every profile profiles.ini names, in the deb's folder, the newer XDG
# one and the snap's (70-firefox.sh moves you off the snap, but leaves its copy).
bc_firefox_profiles() {
    local root ini path rel
    for root in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox"; do
        ini="$root/profiles.ini"
        [[ -f "$ini" ]] || continue
        while IFS='|' read -r path rel; do
            [[ -n "$path" ]] || continue
            if [[ "$rel" == 0 || "$path" == /* ]]; then
                [[ -d "$path" ]] && printf '%s\n' "$path"
            else
                [[ -d "$root/$path" ]] && printf '%s\n' "$root/$path"
            fi
        done < <(awk -F= '
            /^\[/ { if (p != "") print p "|" r; p = ""; r = 1; prof = ($0 ~ /^\[Profile/); next }
            prof && $1 == "Path"       { p = substr($0, 6) }
            prof && $1 == "IsRelative" { r = $2 }
            END { if (p != "") print p "|" r }' "$ini")
    done
}

# Chromium family: every folder with a Preferences file in it (Default, Profile 1…).
bc_chromium_profiles() {
    local d
    for d in "${BC_DATA[$1]}"/*/; do
        [[ -f "$d/Preferences" ]] && printf '%s\n' "${d%/}"
    done
}

bc_profiles() {
    if [[ "$1" == firefox ]]; then bc_firefox_profiles; else bc_chromium_profiles "$1"; fi
}

# ── is it open? ──────────────────────────────────────────────────────────────
# Deleting files under a running browser breaks its profile, so an open browser
# is skipped. Told by the lock each one holds, and only while the process that
# made it is alive: a crash leaves the lock behind.
# _bc_lock_alive LOCK PID  — LOCK is there and PID (read from it) is running.
_bc_lock_alive() {
    local lock="$1" pid="$2"
    [[ -L "$lock" ]] || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0   # a lock we cannot read: assume open
    kill -0 "$pid" 2>/dev/null
}

bc_running() {
    local id="$1" p t
    if [[ "$id" == firefox ]]; then
        while IFS= read -r p; do
            # `lock -> 127.0.1.1:+PID`
            t="$(readlink "$p/lock" 2>/dev/null || true)"
            _bc_lock_alive "$p/lock" "${t##*+}" && return 0
        done < <(bc_firefox_profiles)
        return 1
    fi
    # `SingletonLock -> HOSTNAME-PID`
    t="$(readlink "${BC_DATA[$id]}/SingletonLock" 2>/dev/null || true)"
    _bc_lock_alive "${BC_DATA[$id]}/SingletonLock" "${t##*-}"
}

# ── deleting ─────────────────────────────────────────────────────────────────
BC_REMOVED=0

# _bc_rm DIR PATTERN…  — delete what each glob matches inside DIR. compgen, not
# a bare glob: names like "Top Sites*" have spaces in them.
_bc_rm() {
    local dir="$1" pat f; shift
    [[ -d "$dir" ]] || return 0
    for pat in "$@"; do
        while IFS= read -r f; do
            [[ -e "$f" || -L "$f" ]] || continue
            run rm -rf -- "$f"
            BC_REMOVED=$(( BC_REMOVED + 1 ))
        done < <(compgen -G "$dir/$pat" || true)
    done
}

# _bc_rm_except DIR KEEP-GLOB…  — delete everything in DIR but what the globs
# match: the site data folders that also hold an extension's own data.
_bc_rm_except() {
    local dir="$1" f name k keep; shift
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/* "$dir"/.[!.]*; do
        [[ -e "$f" || -L "$f" ]] || continue
        name="${f##*/}"; keep=0
        for k in "$@"; do
            # shellcheck disable=SC2053  # the glob IS the point
            [[ "$name" == $k ]] && { keep=1; break; }
        done
        (( keep )) && continue
        run rm -rf -- "$f"
        BC_REMOVED=$(( BC_REMOVED + 1 ))
    done
}

# _bc_py WHAT FILE  — the parts a file delete cannot reach: a database or a JSON
# file that holds things to keep next to things to delete. See browser-clean/clean.py.
_bc_py() {
    [[ -f "$2" ]] || return 0
    if ! has_cmd python3; then
        warn "No python3 — ${2/#$HOME/\~} not cleaned ($1)."
        return 1
    fi
    run python3 -I "$BLE_ROOT/browser-clean/clean.py" "$1" "$2"
}

bc_clean_firefox_profile() {
    local p="$1" rc=0
    _bc_rm "$p" \
        'cookies.sqlite*' 'webappsstore.sqlite*' 'formhistory.sqlite*' \
        'permissions.sqlite*' 'content-prefs.sqlite*' 'cert_override.txt' \
        'favicons.sqlite*' 'protections.sqlite*' 'domain_to_categories.sqlite*' \
        'sessionstore.jsonlz4' 'sessionstore-backups' \
        'SiteSecurityServiceState.*' 'AlternateServices.*' 'serviceworker.txt' \
        'cache2' 'startupCache' 'thumbnails' 'shader-cache' 'OfflineCache' \
        'storage/temporary' 'storage/to-be-removed'
    # Site data, minus each extension's own (moz-extension+++…) and Firefox's (chrome).
    _bc_rm_except "$p/storage/default" 'moz-extension+++*'
    _bc_rm_except "$p/storage/permanent" 'chrome' 'moz-extension+++*'
    # History and bookmarks share places.sqlite: the history goes, the bookmarks stay.
    _bc_py firefox-places "$p/places.sqlite" || rc=1
    # The disk cache lives outside the profile, under the profile's folder name.
    _bc_rm "$HOME/.cache/mozilla/firefox" "${p##*/}"
    _bc_rm "$HOME/snap/firefox/common/.cache/mozilla/firefox" "${p##*/}"
    return "$rc"
}

bc_clean_chromium_profile() {
    local id="$1" p="$2" rc=0 sub
    # Network/ in newer builds, the profile itself in older ones: both are tried.
    for sub in "$p" "$p/Network"; do
        _bc_rm "$sub" \
            'Cookies' 'Cookies-journal' 'Safe Browsing Cookies*' \
            'TransportSecurity' 'Trust Tokens*' 'Reporting and NEL*' \
            'Network Persistent State' 'SCT Auditing Pending Reports' 'Device Bound Sessions*'
    done
    _bc_rm "$p" \
        'History' 'History-journal' 'History Provider Cache' 'Visited Links' \
        'Top Sites*' 'Shortcuts*' 'Network Action Predictor*' 'Favicons*' \
        'Sessions' 'Sessions_Encrypted' 'Current Session' 'Current Tabs' 'Last Session' 'Last Tabs' \
        'Local Storage' 'Session Storage' 'File System' 'blob_storage' 'WebStorage' 'databases' \
        'Shared Dictionary' 'Service Worker/CacheStorage' \
        'ServerCertificate*' 'MediaDeviceSalts*' 'Media History*' 'DIPS*' 'Conversions*' \
        'Download Service' 'Platform Notifications' 'PersistentOriginTrials' \
        'Site Characteristics Database' 'heavy_ad_intervention_opt_out.db*' \
        'Cache' 'Code Cache' 'GPUCache' 'DawnGraphiteCache' 'DawnWebGPUCache'
    # Site data, minus each extension's own.
    _bc_rm_except "$p/IndexedDB" 'chrome-extension_*'
    _bc_rm_except "$p/Storage" 'ext'
    # Web Data holds the cards and addresses AND the form history; Preferences
    # holds the settings AND the per-site permissions and zoom.
    _bc_py chromium-webdata "$p/Web Data" || rc=1
    _bc_py chromium-prefs "$p/Preferences" || rc=1
    _bc_rm "${BC_CACHE[$id]}" "${p##*/}"
    return "$rc"
}

# bc_clean ID  — clean every profile of ID now. 0 cleaned, 1 something failed,
# 2 skipped (not installed, or open). Stamps ID when it was cleaned and is ticked.
bc_clean() {
    local id="$1" name="${BC_NAME[$1]}" p n=0 rc=0
    if ! bc_installed "$id"; then
        skip "$name is not installed — nothing to clean."
        return 2
    fi
    if bc_running "$id"; then
        warn "$name is open — not cleaned. Close it, then run 'b-browser-clean now $id'."
        return 2
    fi
    BC_REMOVED=0
    while IFS= read -r p; do
        n=$(( n + 1 ))
        if [[ "$id" == firefox ]]; then
            bc_clean_firefox_profile "$p" || rc=1
        else
            bc_clean_chromium_profile "$id" "$p" || rc=1
        fi
    done < <(bc_profiles "$id")
    if (( rc )); then
        warn "$name: cleaned only in part — see above. It is tried again at the next boot."
        return 1
    fi
    bc_ticked "$id" && bc_stamp "$id"
    if (( n == 0 )); then
        skip "$name has no profile yet — nothing to clean."
    elif [[ "$DRY_RUN" == true ]]; then
        skip "$name: dry run — $BC_REMOVED item(s) in $n profile(s) would be deleted."
    else
        ok "$name cleaned: $BC_REMOVED item(s) deleted in $n profile(s). Passwords, cards, addresses, bookmarks and extensions kept."
    fi
    return 0
}
