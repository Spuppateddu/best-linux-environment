// Zen browser — portable configuration prefs.
//
// This is a hand-curated subset of prefs.js containing ONLY durable settings
// (window/toolbar layout, fonts, Zen view options) — no personal data. Zen reads
// user.js at every startup and applies these over prefs.js, so it is safe to copy
// between machines and safe to keep in a public repo. Deliberately excluded from
// the original prefs.js: the fxaccounts device name, telemetry client IDs, the
// nimbus profileId, session/build timestamps, and migration bookkeeping.
//
// Note: values here are re-applied on every launch. To change one permanently on
// a machine, edit it here (and re-run install.sh) rather than only in the UI.

// ── Toolbar / sidebar layout (the main "same layout" pref) ───────────────────
user_pref("browser.uiCustomization.state", "{\"placements\":{\"widget-overflow-fixed-list\":[],\"unified-extensions-area\":[\"ublock0_raymondhill_net-browser-action\"],\"nav-bar\":[\"back-button\",\"forward-button\",\"stop-reload-button\",\"customizableui-special-spring1\",\"vertical-spacer\",\"urlbar-container\",\"customizableui-special-spring2\",\"unified-extensions-button\",\"_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action\",\"wappalyzer_crunchlabz_com-browser-action\",\"_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action\"],\"toolbar-menubar\":[\"menubar-items\"],\"TabsToolbar\":[\"tabbrowser-tabs\"],\"vertical-tabs\":[],\"PersonalToolbar\":[\"import-button\",\"personal-bookmarks\"],\"zen-sidebar-top-buttons\":[\"zen-toggle-compact-mode\"],\"zen-sidebar-foot-buttons\":[\"downloads-button\",\"zen-workspaces-button\",\"zen-create-new-button\"]},\"seen\":[\"developer-button\",\"screenshot-button\",\"ublock0_raymondhill_net-browser-action\",\"_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action\",\"wappalyzer_crunchlabz_com-browser-action\",\"_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action\"],\"dirtyAreaCache\":[\"nav-bar\",\"vertical-tabs\",\"zen-sidebar-foot-buttons\",\"PersonalToolbar\",\"unified-extensions-area\",\"toolbar-menubar\",\"TabsToolbar\",\"zen-sidebar-top-buttons\"],\"currentVersion\":24,\"newElementCount\":2}");
user_pref("sidebar.visibility", "hide-sidebar");

// ── Zen view options ─────────────────────────────────────────────────────────
user_pref("zen.glance.enabled", false);
user_pref("zen.tabs.select-recently-used-on-close", false);
user_pref("zen.tabs.show-newtab-vertical", false);
user_pref("zen.view.compact.enable-at-startup", true);
user_pref("zen.view.show-newtab-button-top", false);
user_pref("zen.view.use-single-toolbar", false);
user_pref("zen.workspaces.separate-essentials", false);
// Web content flush to the chrome: no gap around it, square corners (border 0).
// Zen reads these ints and drives --zen-element-separation / --zen-border-radius.
user_pref("zen.theme.content-element-separation", 0);
user_pref("zen.theme.border-radius", 0);
// Keep the shipped keyboard-shortcuts file from being regenerated on first run.
user_pref("zen.keyboard.shortcuts.version", 19);
// Skip the first-run onboarding on a freshly provisioned machine.
user_pref("zen.welcome-screen.seen", true);

// ── Fonts ────────────────────────────────────────────────────────────────────
user_pref("font.name.serif.x-western", "CaskaydiaCove Nerd Font");

// ── General browsing behaviour ───────────────────────────────────────────────
user_pref("browser.startup.page", 1);
user_pref("browser.download.useDownloadDir", false); // always ask where to save
user_pref("browser.urlbar.placeholderName", "DuckDuckGo");
user_pref("browser.urlbar.placeholderName.private", "DuckDuckGo");
