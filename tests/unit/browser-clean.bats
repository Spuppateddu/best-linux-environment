#!/usr/bin/env bats
# browser-clean/: b-browser-clean, lib/browser-clean.sh, clean.py, and the
# module that links it. Fake profiles in a temp HOME; no real browser runs.

load helpers

eval "$(declare -f setup | sed '1s/^setup/helpers_setup/')"
setup() {
    helpers_setup
    # Never the repo's own settings.local.
    export BLE_SETTINGS_LOCAL="$BATS_TEST_TMPDIR/settings.local"
    : > "$BLE_SETTINGS_LOCAL"
    export FF="$HOME/.mozilla/firefox/abc.default"
    export CH="$HOME/.config/google-chrome/Default"
}

bc() { run bash "$REPO/browser-clean/b-browser-clean" "$@"; }

# A Firefox profile with one bookmarked page and one page that is only history.
make_firefox() {
    fake_cmd firefox 'exit 0'
    mkdir -p "$FF/extensions" "$FF/storage/default/https+++example.com" \
        "$FF/storage/default/moz-extension+++1234" "$FF/sessionstore-backups" \
        "$HOME/.cache/mozilla/firefox/abc.default/cache2"
    printf '[Profile0]\nName=default\nIsRelative=1\nPath=abc.default\n\n[General]\nVersion=2\n' \
        > "$HOME/.mozilla/firefox/profiles.ini"
    local f
    for f in cookies.sqlite formhistory.sqlite permissions.sqlite favicons.sqlite \
             sessionstore.jsonlz4 logins.json key4.db autofill-profiles.json prefs.js \
             extensions/vimium.xpi; do
        echo x > "$FF/$f"
    done
    python3 -I - "$FF/places.sqlite" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER,
    last_visit_date INTEGER, typed INTEGER, origin_id INTEGER);
CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER);
CREATE TABLE moz_inputhistory (place_id INTEGER, input TEXT);
CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, fk INTEGER, title TEXT);
CREATE TABLE moz_keywords (id INTEGER PRIMARY KEY, place_id INTEGER);
CREATE TABLE moz_origins (id INTEGER PRIMARY KEY, host TEXT);
INSERT INTO moz_origins VALUES (1, 'kept.org'), (2, 'visited.com');
INSERT INTO moz_places VALUES (1, 'https://kept.org/', 5, 99, 1, 1), (2, 'https://visited.com/', 3, 99, 1, 2);
INSERT INTO moz_historyvisits VALUES (1, 1), (2, 2);
INSERT INTO moz_inputhistory VALUES (2, 'vis');
INSERT INTO moz_bookmarks VALUES (1, NULL, 'menu'), (2, 1, 'Kept');
""")
c.commit()
PY
}

# A Chrome profile with a card and a typed form value in Web Data.
make_chrome() {
    fake_cmd google-chrome-stable 'exit 0'
    mkdir -p "$CH/Local Extension Settings/abc" "$CH/Extensions/abc" "$CH/Sessions" \
        "$CH/Local Storage/leveldb" "$CH/IndexedDB/https_example.com_0.indexeddb.leveldb" \
        "$CH/IndexedDB/chrome-extension_abc_0.indexeddb.leveldb" "$CH/Network" \
        "$HOME/.cache/google-chrome/Default/Cache"
    local f
    for f in History History-journal "Top Sites" Cookies Network/Cookies Favicons \
             "Login Data" Bookmarks "Secure Preferences"; do
        echo x > "$CH/$f"
    done
    cat > "$CH/Preferences" <<'JSON'
{"browser":{"show_home_button":true},
 "profile":{"content_settings":{"exceptions":{"notifications":{"https://a.com,*":{"setting":1}},"geolocation":{}}}},
 "partition":{"per_host_zoom_levels":{"x":{"a.com":{"zoom_level":1.0}}}}}
JSON
    python3 -I - "$CH/Web Data" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE autofill (name TEXT, value TEXT);
CREATE TABLE credit_cards (guid TEXT, name_on_card TEXT);
CREATE TABLE addresses (guid TEXT);
INSERT INTO autofill VALUES ('q', 'typed once');
INSERT INTO credit_cards VALUES ('g', 'Card Owner');
INSERT INTO addresses VALUES ('a');
""")
c.commit()
PY
}

sql() { python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])' "$1" "$2"; }

@test "browser clean: Firefox loses history, cookies, site data and tabs; keeps passwords, cards, bookmarks, extensions" {
    make_firefox
    bc now firefox
    [ "$status" -eq 0 ]
    for f in cookies.sqlite formhistory.sqlite permissions.sqlite favicons.sqlite \
             sessionstore.jsonlz4 sessionstore-backups storage/default/https+++example.com; do
        [ ! -e "$FF/$f" ] || { echo "still here: $f"; false; }
    done
    [ ! -e "$HOME/.cache/mozilla/firefox/abc.default" ]
    for f in logins.json key4.db autofill-profiles.json prefs.js extensions/vimium.xpi \
             storage/default/moz-extension+++1234 places.sqlite; do
        [ -e "$FF/$f" ] || { echo "gone: $f"; false; }
    done
    [ "$(sql "$FF/places.sqlite" 'SELECT group_concat(url) FROM moz_places')" = "https://kept.org/" ]
    [ "$(sql "$FF/places.sqlite" 'SELECT count(*) FROM moz_historyvisits')" = 0 ]
    [ "$(sql "$FF/places.sqlite" 'SELECT count(*) FROM moz_inputhistory')" = 0 ]
    [ "$(sql "$FF/places.sqlite" 'SELECT visit_count FROM moz_places')" = 0 ]
    [ "$(sql "$FF/places.sqlite" 'SELECT group_concat(host) FROM moz_origins')" = "kept.org" ]
    [ "$(sql "$FF/places.sqlite" 'SELECT count(*) FROM moz_bookmarks')" = 2 ]
}

@test "browser clean: Chrome loses history, cookies, site data, form history, permissions; keeps passwords, cards, bookmarks, extensions" {
    make_chrome
    bc now google-chrome
    [ "$status" -eq 0 ]
    for f in History History-journal "Top Sites" Cookies Network/Cookies Favicons Sessions \
             "Local Storage" IndexedDB/https_example.com_0.indexeddb.leveldb; do
        [ ! -e "$CH/$f" ] || { echo "still here: $f"; false; }
    done
    [ ! -e "$HOME/.cache/google-chrome/Default" ]
    for f in "Login Data" Bookmarks "Secure Preferences" Preferences "Web Data" \
             "Local Extension Settings/abc" Extensions/abc IndexedDB/chrome-extension_abc_0.indexeddb.leveldb; do
        [ -e "$CH/$f" ] || { echo "gone: $f"; false; }
    done
    [ "$(sql "$CH/Web Data" 'SELECT count(*) FROM autofill')" = 0 ]
    [ "$(sql "$CH/Web Data" 'SELECT name_on_card FROM credit_cards')" = "Card Owner" ]
    [ "$(sql "$CH/Web Data" 'SELECT count(*) FROM addresses')" = 1 ]
    run jq -c '[.profile.content_settings.exceptions, .partition.per_host_zoom_levels, .browser.show_home_button]' "$CH/Preferences"
    [ "$output" = '[{"notifications":{},"geolocation":{}},{},true]' ]
}

@test "browser clean: an open browser is not touched; a lock left by a crash is no reason to skip" {
    make_firefox
    sleep 30 & local pid=$!
    ln -s "127.0.1.1:+$pid" "$FF/lock"
    bc now firefox
    kill "$pid"
    [[ "$output" == *"Firefox is open — not cleaned"* ]]
    [ -e "$FF/cookies.sqlite" ]

    # The same lock, but its process is gone.
    bc now firefox
    [ "$status" -eq 0 ]
    [ ! -e "$FF/cookies.sqlite" ]
}

@test "browser clean: Chrome's SingletonLock of a running process skips it" {
    make_chrome
    sleep 30 & local pid=$!
    ln -s "myhost-$pid" "$HOME/.config/google-chrome/SingletonLock"
    bc now google-chrome
    kill "$pid"
    [[ "$output" == *"Google Chrome is open — not cleaned"* ]]
    [ -e "$CH/History" ]
}

@test "browser clean: ticking starts the timer — nothing goes until the days have passed" {
    make_firefox
    ble "source '$REPO/lib/browser-clean.sh'; BC_NOW=1000000 bc_set_ticked firefox"
    [ "$status" -eq 0 ]
    [ "$(cat "$BLE_STATE_DIR/browser-clean")" = "firefox 1000000" ]

    # Six days later: not due.
    BC_NOW=$(( 1000000 + 6 * 86400 )) bc run
    [ "$status" -eq 0 ]
    [[ "$output" == *"next clean in 1 day"* ]]
    [ -e "$FF/cookies.sqlite" ]

    # Seven days later: cleaned, and the timer starts again from then.
    BC_NOW=$(( 1000000 + 7 * 86400 )) bc run
    [ "$status" -eq 0 ]
    [ ! -e "$FF/cookies.sqlite" ]
    [ "$(cat "$BLE_STATE_DIR/browser-clean")" = "firefox $(( 1000000 + 7 * 86400 ))" ]
}

@test "browser clean: BLE_BROWSER_CLEAN_DAYS sets the days; a bad value falls back to 7" {
    make_firefox
    ble "source '$REPO/lib/browser-clean.sh'; BC_NOW=1000000 bc_set_ticked firefox"
    echo BLE_BROWSER_CLEAN_DAYS=2 > "$BLE_SETTINGS_LOCAL"
    BC_NOW=$(( 1000000 + 2 * 86400 )) bc run
    [ ! -e "$FF/cookies.sqlite" ]

    echo BLE_BROWSER_CLEAN_DAYS=zero > "$BLE_SETTINGS_LOCAL"
    BC_NOW=$(( 1000000 + 2 * 86400 )) bc status
    [[ "$output" == *"not a whole number of days"* ]]
    [[ "$output" == *"Every 7 day(s)"* ]]
}

@test "browser clean: re-ticking keeps the date; unticking drops the browser" {
    ble "source '$REPO/lib/browser-clean.sh'; BC_NOW=100 bc_set_ticked firefox; BC_NOW=500 bc_set_ticked firefox brave"
    [ "$(cat "$BLE_STATE_DIR/browser-clean")" = "$(printf 'firefox 100\nbrave 500')" ]
    ble "source '$REPO/lib/browser-clean.sh'; bc_set_ticked brave"
    [ "$(cat "$BLE_STATE_DIR/browser-clean")" = "brave 500" ]
}

@test "browser clean: run with nothing ticked does nothing" {
    make_firefox
    bc run
    [ "$status" -eq 0 ]
    [[ "$output" == *"No browser is ticked"* ]]
    [ -e "$FF/cookies.sqlite" ]
}

@test "browser clean: --dry-run deletes nothing and keeps the timer" {
    make_firefox
    ble "source '$REPO/lib/browser-clean.sh'; BC_NOW=1000000 bc_set_ticked firefox"
    BC_NOW=$(( 1000000 + 8 * 86400 )) bc run --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would be deleted"* ]]
    [ -e "$FF/cookies.sqlite" ]
    [ "$(sql "$FF/places.sqlite" 'SELECT count(*) FROM moz_places')" = 2 ]
    [ "$(cat "$BLE_STATE_DIR/browser-clean")" = "firefox 1000000" ]
}

@test "browser clean: a browser that is not installed is skipped, not an error" {
    ble "source '$REPO/lib/browser-clean.sh'; BC_NOW=0 bc_set_ticked brave"
    bc run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Brave is not installed"* ]]
}

@test "browser clean: an unknown browser name is refused" {
    bc now netscape
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown browser 'netscape'"* ]]
}

@test "27-browser-clean: links b-browser-clean into ~/.local/bin, and a re-run changes nothing" {
    run bash "$REPO/basic/27-browser-clean.sh"
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.local/bin/b-browser-clean")" = "$REPO/browser-clean/b-browser-clean" ]
    run bash "$REPO/basic/27-browser-clean.sh"
    [[ "$output" == *"already linked"* ]]
    # Through the link, it still finds the repo.
    run "$HOME/.local/bin/b-browser-clean" status
    [ "$status" -eq 0 ]
}
