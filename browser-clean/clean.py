#!/usr/bin/env python3
"""The part of b-browser-clean a file delete cannot do: a file that holds things
to keep next to things to delete. Run by lib/browser-clean.sh, with the browser
closed, as `python3 -I clean.py WHAT FILE`:

  firefox-places FILE    places.sqlite: delete the history, keep the bookmarks
  chromium-webdata FILE  Web Data: delete the form history, keep cards and addresses
  chromium-prefs FILE    Preferences: delete the per-site permissions and zoom,
                         keep every setting
"""

import json
import os
import sqlite3
import sys


def tables(con):
    return {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}


def firefox_places(path):
    # Bookmarks and history share moz_places. A place stays if a bookmark or a
    # bookmark keyword points at it; every visit, and every other place, goes.
    con = sqlite3.connect(path, isolation_level=None)
    have = tables(con)
    keep = "SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL"
    if "moz_keywords" in have:
        keep += " UNION SELECT place_id FROM moz_keywords"
    con.execute("BEGIN")
    try:
        for t in (
            "moz_historyvisits", "moz_historyvisits_extra", "moz_inputhistory",
            "moz_places_metadata", "moz_places_metadata_search_queries",
            "moz_previews_tombstones", "moz_newtab_story_click",
            "moz_newtab_story_impression", "moz_newtab_shortcuts_interaction",
        ):
            if t in have:
                con.execute(f"DELETE FROM {t}")
        # Annotations are mostly the downloads list: gone with their places.
        if "moz_annos" in have:
            con.execute(f"DELETE FROM moz_annos WHERE place_id NOT IN ({keep})")
        if "moz_places_extra" in have:
            con.execute(f"DELETE FROM moz_places_extra WHERE place_id NOT IN ({keep})")
        con.execute(f"DELETE FROM moz_places WHERE id NOT IN ({keep})")
        cols = {r[1] for r in con.execute("PRAGMA table_info(moz_places)")}
        sets = ["visit_count = 0", "last_visit_date = NULL"]
        if "typed" in cols:
            sets.append("typed = 0")
        con.execute("UPDATE moz_places SET " + ", ".join(sets))
        if "moz_origins" in have:
            con.execute(
                "DELETE FROM moz_origins WHERE id NOT IN "
                "(SELECT origin_id FROM moz_places WHERE origin_id IS NOT NULL)"
            )
        con.execute("COMMIT")
    except Exception:
        con.execute("ROLLBACK")
        raise
    # The deleted rows are still in the file's free pages until it is rewritten.
    con.execute("VACUUM")
    con.close()


def chromium_webdata(path):
    # `autofill` (older builds) and `autocomplete` (newer) are what you typed in
    # forms. Cards, addresses, IBANs and the search engines are other tables.
    con = sqlite3.connect(path, isolation_level=None)
    have = tables(con)
    con.execute("BEGIN")
    for t in ("autofill", "autocomplete"):
        if t in have:
            con.execute(f"DELETE FROM {t}")
    con.execute("COMMIT")
    con.execute("VACUUM")
    con.close()


def chromium_prefs(path):
    # profile.content_settings.exceptions: one dict per kind (camera, cookies,
    # notifications, site engagement…) of `site pattern → setting`. Each is
    # emptied, so every site is back to the default. Zoom is per host, apart.
    with open(path, encoding="utf-8") as f:
        prefs = json.load(f)
    changed = False
    exc = prefs.get("profile", {}).get("content_settings", {}).get("exceptions")
    if isinstance(exc, dict):
        for kind in exc:
            if exc[kind]:
                exc[kind] = {}
                changed = True
    zoom = prefs.get("partition", {}).get("per_host_zoom_levels")
    if zoom:
        prefs["partition"]["per_host_zoom_levels"] = {}
        changed = True
    if not changed:
        return
    tmp = f"{path}.ble-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(prefs, f, separators=(",", ":"))
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)


def main():
    jobs = {
        "firefox-places": firefox_places,
        "chromium-webdata": chromium_webdata,
        "chromium-prefs": chromium_prefs,
    }
    if len(sys.argv) != 3 or sys.argv[1] not in jobs:
        sys.exit(__doc__)
    try:
        jobs[sys.argv[1]](sys.argv[2])
    except (sqlite3.Error, OSError, ValueError) as e:
        sys.exit(f"{sys.argv[1]} {sys.argv[2]}: {e}")


if __name__ == "__main__":
    main()
