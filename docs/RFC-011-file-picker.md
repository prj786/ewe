# RFC-011 (draft) — One file picker: ewe draws every Open / Save / Open With dialog

**Status:** BUILT 2026-11-22 on branch `file-picker` (ewe + the five app repos),
not committed or released. The owner said "go"; the two open questions were
settled as proposed (dimmed screen, Open with in the same wave). §12 records
what Phase 0 found and how each part was tested.
**Repos touched:** `ewe` (most of it), plus a one-line change in `komble-arch`,
`ewe-settings`, `ewe-sync`, `ewe-safe` and `ewe-apps`.
**Number:** RFC-010 is reserved for eep, so this one is 011. Renumber it if that changes.

---

## 1. The problem

When an app asks you to pick a file (Open, Upload, Save As, Choose folder) or an
app to open something with, you get a different dialog depending on the app: the
GTK3 dialog, the GTK4 one, Qt's, or ewe's own. None of them look like ewe. Sometimes
the dialog also opens **underneath** the app that asked for it, so it looks like
nothing happened.

We want one dialog that looks like ewe, always floats, and is always on top of
the app that asked.

## 2. What is going on today (checked on this box, 2026-11-22)

The routing config is the stock Arch one,
`/usr/share/xdg-desktop-portal/hyprland-portals.conf`, which says
`default=hyprland;gtk`. xdg-desktop-portal-hyprland has no file picker, so
**every portal file dialog is xdg-desktop-portal-gtk's GTK3 dialog**. Many apps
don't use the portal at all and draw a toolkit dialog themselves:

| Apps | How they ask today | What you see | Change needed |
|---|---|---|---|
| ewe Browser (Electron 44), Chrome, VS Code, Slack, Discord, Obsidian | portal (Chromium uses the FileChooser portal when there is one) | GTK3 dialog from the portal | **none**: change where the portal sends it |
| GTK4 apps (GtkFileDialog) | portal when there is one | GTK3 dialog from the portal | none |
| **Komble, Settings, Sync, Safe, ewe Files/Player/Viewer** (Tauri) | `tauri-plugin-dialog` 2.x defaults to the `gtk3` feature, so rfd draws a GtkFileChooserDialog **inside the app** and never asks the portal | GTK3 dialog inside the app | switch the plugin to `xdg-portal` (§6.3) |
| Firefox, GTK3 apps that use GtkFileChooserNative, `<input type=file>` in our Tauri webviews (WebKitGTK 4.1 is GTK3) | in-app GTK3 (Firefox's pref defaults to 2, "portal only under Flatpak/Snap or `GTK_USE_PORTAL`") | GTK3 dialog inside the app | `GTK_USE_PORTAL=1` in the session |
| Qt apps | `QT_QPA_PLATFORMTHEME=qt6ct`, and `colorscheme.sh` writes `standard_dialogs=default` | Qt's own widget dialog | `standard_dialogs=xdgdesktopportal` |
| GIMP and other apps that build GtkFileChooserDialog directly, JetBrains IDEs (Swing), Steam, Wine and Java apps | their own dialogs | their own | **can't change from outside**: these stay as they are, and we document them |

All five Tauri apps call only `open()` / `save()` / folder pick (checked:
`AurInstall`, `Plugins`, `Appearance`, `UserPane`, `WallpaperPane`, `Network`,
`FolderForm`, Player, Viewer, `PdfView`, Safe's SSH-key import). None of them uses
the plugin's `message()` or `ask()` dialogs, which rfd's portal backend would
draw with zenity. Switching them over is safe.

### Why the dialog sometimes opens underneath

The portal dialog is a window owned by another process. Hyprland 0.57.2 does
support linking it to its parent (it offers `zxdg_exporter_v2` and
`xdg_wm_dialog_v1`, checked in the binary), and our only rule for it is
`float = true` (`hyprland.lua`, `portal-file-chooser`). The dialog can still
end up below the app in these cases:

- the parent is **floating** (Settings, Slack, Steam). Clicking it raises it above
  the dialog;
- the parent is **fullscreen or maximised**;
- the parent is an **XWayland** app. The GTK portal can't attach a Wayland dialog to
  an X11 parent, so the dialog is an unrelated window;
- focus or the cursor was on **another monitor** when the dialog opened.

The journal on this box has no "Failed to associate portal window" lines, so I
can't tell from the logs which of these hit you. Phase 0 reproduces each one.
**The design below removes the cause instead of chasing each case.** ewe's picker
is drawn by the shell on the *overlay* layer, which is above every window,
fullscreen windows included. Nothing can stack over it.

## 3. The proposal

1. **The shell draws the picker.** It goes in a new `FilePicker.qml` on a layer-shell
   overlay, the same way the screen-share picker (`SharePicker.qml`) already
   works. Layer surfaces stay in the shell (Rule 3), and the shell is already
   running, so the picker opens instantly with no cold start.
2. **A small daemon, `ewe-portal`, is the portal backend.** It is a Python + D-Bus
   service, like `bt-agent.py` and `logind-bridge.py`, and uses only packages we
   already ship (`python-dbus`, `python-gobject`). It survives shell restarts, as
   [[Process Split — Shell vs Apps]] requires for anything that must outlive the
   shell. If the shell can't answer, it **hands the request to the stock GTK
   dialog**, so file dialogs never break. That is the same fallback
   `ewe-share-picker` uses.
3. **Only the FileChooser and AppChooser interfaces go to ewe.** Everything else
   stays `hyprland;gtk`.
4. **Every app that can be made to ask the portal is made to** (§6.3).

### Rejected

- **A picker mode in ewe Files (a Tauri window).** It would start cold every time
  (0.5–1 s for WebKitGTK), it would be a normal window with the same stacking
  problem, and Tauri can't make layer surfaces.
- **Restyling the GTK dialog with CSS.** It would still be GTK, the Qt and Tauri paths
  wouldn't change, and the stacking problem would stay.
- **Third-party backends (termfilechooser, shana, scriptfm).** They don't look like ewe
  and would be one more upstream to track.

## 4. How it works

```
 app ──portal call──▶ xdg-desktop-portal ──impl.FileChooser / impl.AppChooser──▶ ewe-portal (daemon)
                                                                                     │
          ┌──────────────────────────────────────────────────────────────────────────┤
          │ shell answers                                                            │ shell can't
          ▼                                                                          ▼
 1. write request  $XDG_RUNTIME_DIR/ewe-portal/<id>.json (0600)          forward the same call to
 2. mkfifo         $XDG_RUNTIME_DIR/ewe-portal/<id>.answer               org.freedesktop.impl.portal.desktop.gtk
 3. qs ipc call filepicker open <id>                                     (stock dialog), relay its answer
 4. FilePicker.qml opens on the requesting window's monitor
 5. shell writes ONE JSON line to the fifo:  {"ok":true,"paths":[…],"choices":[…],"filter":n}
                                        or:  {"ok":false}            (cancelled)
 6. daemon turns paths into file:// URIs, replies (0 = ok, 1 = cancelled)
```

- **The app cancels** (the portal calls `Request.Close`): the daemon runs
  `qs ipc call filepicker close <id>`.
- **Two requests at once:** they queue, and one card shows at a time.
- **Shell dies while a dialog is open:** the daemon gives up after a timeout (no
  answer and the IPC target is gone) and replies "cancelled".
- **Which window asked:** `parent_window` is an opaque `wayland:` or `x11:` handle,
  so the shell uses Hyprland's focused window at request time (you just clicked
  "Upload" in it). It shows that app's icon and name and centres the card over
  that window, kept inside the monitor.
- **The daemon does the fiddly work, so the QML stays small and safe:**
  - decoding the `ay` byte-string paths (`current_folder`, `current_file`);
  - turning MIME filters into glob lists from shared-mime-info (`globs2` +
    `subclasses`), so the QML only matches globs and can feed them straight to
    `FolderListModel.nameFilters`;
  - URI percent-encoding of the answer;
  - reading `recently-used.xbel` and GTK bookmarks;
  - adding the picked file to Recent.

## 5. What the picker looks like

It follows ewe Files' layout, so the desktop has one file look: places on the
left, a path bar on top, the list in the middle and the actions at the bottom.
It uses design tokens only (Rule 8) and follows the scheme, accent, text size,
light/dark and Reduce motion like every other shell surface.

```
╭──────────────────────────────────────────────────────────────────────────╮
│ (app icon) ewe Browser wants a file  ·  "Upload"                      ✕   │
├──────────────┬───────────────────────────────────────────────────────────┤
│ Recent       │  ‹ ›  Home › Documents › Invoices          [search]  ▦ ☰ │
│ Home         │  ───────────────────────────────────────────────────────  │
│ Desktop      │  📁 2026                                         —   Nov 3 │
│ Documents    │  📄 march.pdf                               212 KB   Mar 4 │
│ Downloads    │  📄 april.pdf                               198 KB   Apr 2 │
│ Pictures     │                                                           │
│ Nextcloud    │                                                           │
│ (synced …)   │                                                           │
│ (drives …)   │                                                           │
├──────────────┴───────────────────────────────────────────────────────────┤
│ [PDF files ▾]  [choices…]                          Cancel   [ Upload ]   │
╰──────────────────────────────────────────────────────────────────────────╯
```

- **Modes:** open one file, open several (checkmarks, and the button reads "Open 3"),
  choose a folder (files greyed out; the button picks the current folder),
  **Save** (a name field with the base name preselected, a New folder button, and an
  inline "Replace ‘x.pdf’?" check), Save several (pick a folder), and **Open With**
  (§5.1).
- **Places:** Recent, the XDG folders, Nextcloud when mounted (`ewe-files status`),
  ewe-sync's folders (`sync-folders.json`), your Places plugin folders
  (`apps.places`), GTK bookmarks (the ones ewe Files uses) and removable drives
  under `/run/media/$USER`.
- **Keyboard:** arrows, type to jump to a name, Enter (open folder / accept),
  Backspace or Alt+Up (go up a folder), Alt+←/→ (back and forward), Ctrl+L
  (type a path; `~` and `/` start it too), Ctrl+F (search), Ctrl+H (hidden
  files), Space (preview), Esc (cancel). Hyprland's own keybinds keep working.
- **Filters and extra options:** the app's filters go in a dropdown. The app's
  extra options (`choices`, e.g. "encoding" or "open read-only") show as
  dropdowns or checkboxes next to it.
- **Remembers** the last folder for each app, plus list/grid and hidden-files
  choices, in `~/.local/state/ewe/filepicker.json`. This is state, not config, so it
  stays out of ewe.conf and isn't synced.
- **Thumbnails** in grid view come from the shared freedesktop cache
  (`~/.cache/thumbnails`, which ewe Files already fills). Only what's on screen is
  loaded, at a small `sourceSize`, so the shell's memory stays low.
- **Behind the card:** a dim scrim covers the requesting window's monitor. Other
  monitors stay usable.

### 5.1 Open With (AppChooser)

This is a compact card: *Open "report.pdf" with*. It shows the apps the portal
offers with their icons (from DesktopEntries), with your last choice preselected.
`UpdateChoices` refreshes the list live. If no app fits, the card offers "Find an
app in Komble…" (`komble --search`). ewe Files' own Open With card already uses
ewe's design and stays as it is.

## 6. The pieces

### 6.1 `ewe` repo

| Piece | Where | Notes |
|---|---|---|
| Daemon | `bin/ewe-portal` (Python) | D-Bus name `org.freedesktop.impl.portal.desktop.ewe` at `/org/freedesktop/portal/desktop`. Implements `impl.portal.FileChooser` (`OpenFile`, `SaveFile`, `SaveFiles`), `impl.portal.AppChooser` (`ChooseApplication`, `UpdateChoices`) and `impl.portal.Request` (`Close`). Uses async D-Bus replies on a GLib loop. CLI: `ewe-portal status` and `ewe-portal test open\|save\|folder\|app`, which calls the **real** portal like an app would. Both print JSON and exit 0 (Rule 5). |
| Portal file | `system/portal/ewe.portal` → `/usr/share/xdg-desktop-portal/portals/` | `DBusName=org.freedesktop.impl.portal.desktop.ewe`, `Interfaces=…FileChooser;…AppChooser;` |
| Routing | `system/portal/hyprland-portals.conf` → `/etc/xdg/xdg-desktop-portal/` | `default=hyprland;gtk`, `org.freedesktop.impl.portal.FileChooser=ewe;gtk`, `org.freedesktop.impl.portal.AppChooser=ewe;gtk`. It goes in `/etc/xdg` because the `/usr/share` file belongs to xdph. Phase 0 confirms the lookup order. |
| Activation | `systemd/ewe-portal.service` (user unit) and the D-Bus `.service` file with `SystemdService=` | Started on first use and kept running |
| Picker UI | `dotfiles/quickshell/FilePicker.qml`, `AppChooser.qml` (+ small components) | Loaded through a `Loader` **only while a request is open**. That limits crash risk and memory. |
| Session env | `dotfiles/hypr/start-hyprland.sh` | `export GTK_USE_PORTAL=1`. Don't set `GDK_DEBUG=portals` unless Phase 0 finds a GTK4 app that needs it. |
| Qt | `dotfiles/quickshell/scripts/colorscheme.sh` (~line 480) | `standard_dialogs=xdgdesktopportal` for qt6ct and qt5ct |
| Window rule | `hyprland.lua` | Keep `portal-file-chooser` for the GTK fallback. Phase 0 decides whether leftover in-app dialogs need an extra rule. |
| Checks | `phases/90-postcheck.sh`, Settings → System → Desktop portals (`Settings.qml` ~655, `ewe-settings` `backend.rs` ~1710) | New rows: "portal: ewe file picker routed" and "Portal: ewe" |
| Install paths | PKGBUILD **and** `install.sh` / phase 30 | Both must produce the same paths (the ISO-parity lesson) |

### 6.2 Contracts (public API, Rule 4: these names stick once shipped)

- D-Bus name: `org.freedesktop.impl.portal.desktop.ewe`.
- IPC targets: **`filepicker`** (`open <id>`, `close <id>`, `select <id> <json>`
  for scripted tests) and **`appchooser`** (`open`, `close`, `select`).
  `picker` is already taken by the screen-share picker.
- Runtime files: `$XDG_RUNTIME_DIR/ewe-portal/<id>.json` (the request) and
  `<id>.answer` (a fifo for one JSON line).
- State file: `~/.local/state/ewe/filepicker.json`.
- No secrets anywhere. File paths are never written to ewe.conf.

### 6.3 Making every app ask the portal

| Repo | Change | Version |
|---|---|---|
| komble-arch, ewe-settings, ewe-sync, ewe-safe (`app/src-tauri`), ewe-apps (player + viewer) | `tauri-plugin-dialog = { version = "2", default-features = false, features = ["xdg-portal"] }` | patch bump each |
| ewe | `GTK_USE_PORTAL=1`, qt6ct `standard_dialogs` | in 0.48.0-beta |
| ewe-browser | **nothing**: verify only | — |

## 7. Phases

| # | What | Done when |
|---|---|---|
| **0** | **Audit and reproduce** (small). For each app in §2, watch `busctl --user monitor org.freedesktop.portal.Desktop` while opening a dialog and record which path it takes. Reproduce "underneath" with a floating, a maximised, a fullscreen and an XWayland parent, and with two monitors. Confirm the portal config lookup order (`/usr/lib/xdg-desktop-portal -v`). Confirm the qt6ct `xdgdesktopportal` value and that `Qt.labs.folderlistmodel` imports inside `qs`. | A table of app → path and which "underneath" cases reproduce, written into this RFC |
| **1** | **Plumbing with GTK still drawing** (small). `ewe-portal` as a **pure pass-through** to the GTK backend, packaged, routed and postchecked. This tests the risky part (routing, activation, both install paths) before any UI exists. | Every app in the matrix still opens its dialog, now through `ewe-portal` (visible in its log) |
| **2** | **FilePicker.qml** (large). Open, several files, folder, Save, Save several; places, path bar, filters, choices, keyboard; daemon ↔ shell protocol; fallback when the shell is missing; queue; Close. | Scripted smoke tests (§8) pass in the nested Hyprland harness, and the manual matrix passes for portal apps |
| **3** | **Every app asks** (small, 6 repos). `GTK_USE_PORTAL`, qt6ct, the five Tauri apps on `xdg-portal`. | The matrix shows the ewe picker everywhere except the documented leftovers |
| **4** | **Open With and polish** (medium). AppChooser card, grid view with cached thumbnails, Recent, search, remembered folders, preview on Space; the Settings avatar uses the picker. | Manual checks pass; the shell's idle memory is unchanged with the picker closed |
| **5** | **Release** (small). `ewe-release` skill, one wave: ewe 0.48.0-beta + patch releases of the five apps, then the ewe-repo publish. Vault updates in §10. | `vault-check.sh` green, `[ewe]` published |

## 8. Tests

- **Daemon unit tests** (`tests/ewe-portal-test.sh` driving `python3 -I`):
  MIME → glob conversion (incl. `image/*` and subclasses); `ay` path decoding;
  URI encoding (spaces, `#`, `%`, non-Latin names); request and answer JSON;
  fallback when `qs` is missing (mocked); Close while open; queueing.
- **Shell smoke** (`ewe-smoke` / `run-ewe/driver.sh`): `ewe-portal test open`
  with filters, choices, `multiple`, `directory`, save with `current_name`, then
  `qs ipc call filepicker select <id> …` as a scripted answer. Check the URIs the
  test call gets back. Also: kill `qs` during a request, which must end in a
  cancel or the GTK fallback, never a hang.
- **Real apps on the owner's box after release:** an ewe Browser upload, Chrome,
  Firefox, VS Code or Slack, Komble/Settings/Sync/Safe/ewe Files, one GTK4 app,
  one Qt app, one Flatpak app (the document portal must export the file).
  Parents: floating, maximised, fullscreen, XWayland, and two monitors.

## 9. Risks

| Risk | Mitigation |
|---|---|
| A QML error in the picker takes the whole shell down | Loaded only while open; the logic lives in the daemon; qmllint plus the smoke run before release |
| `GTK_USE_PORTAL=1` side effects (it also sends GTK3's open-URI calls through the portal; Firefox's old default-browser nag) | Covered in the Phase 3 matrix. If something breaks, drop the env var and use a Firefox pref file instead |
| Slow folders (rclone `~/Nextcloud`, GVFS, big Downloads) | `FolderListModel` lists in the background; show a spinner; never block; load thumbnails only for visible items |
| Shell restart in the middle of a pick | Daemon timeout → cancel. The app just sees "cancelled" |
| rfd's portal backend returns an error instead of falling back when no portal exists | ewe always has the portal (postcheck). The Tauri apps already handle a cancelled or failed pick |
| Keyboard focus: Hyprland refuses to focus a window while a layer surface holds the keyboard exclusively (the Alt+Tab switcher lesson, 2026-10-27) | Copy SharePicker: `Overlay` + `Exclusive` **only while visible**, `None` the moment it closes, so Hyprland can hand focus back to the app that asked. The lock screen always wins. Opening Overview or the launcher on top cancels nothing (test it) |

## 10. Vault, on release (same change)

- `08-Decisions/RFC-011 — One file picker.md` + `Decision Index.md`
- `12-Reference/IPC Verb Reference.md` (`filepicker`, `appchooser`) +
  `ewe-facts.json`
- `03-Components/` note for `ewe-portal`; `12-Reference/Storage Map.md` (state
  file, runtime dir)
- `11-How-We-Work/Troubleshooting Knowledge.md`: "a file dialog looks like GTK
  again" → `ewe-portal status`, the app's dialog path (§2 table), or the shell's
  missing IPC target; plus the list of apps we can't change
- `Quick Answers.md`, `Roadmap and Status.md`, `Version Ledger.md`
- `ewe/CLAUDE.md`: add `filepicker` and `appchooser` to the core IPC targets list;
  bump `VERSION` **and** `Globals.version`
- Site docs: a short "Choosing files" section

## 11. Questions for the owner

1. **Scrim or not?** Proposed: dim the requesting window's monitor, so it's
   clearly modal like the share picker. The alternative is the card alone, so you
   can still click other windows on that monitor while it's open.
2. **Open With in the same wave or later?** Proposed: the same wave (Phase 4),
   because you mentioned picking an app too.

## 12. Built — what Phase 0 found, what changed from the plan, how it was tested

**Phase 0 facts (checked, not assumed):**
- xdg-desktop-portal 1.22 reads the user's routing (`~/.config/xdg-desktop-portal/
  hyprland-portals.conf`) AND the user's portal files (`~/.local/share/
  xdg-desktop-portal/portals/`) before the system's. So the whole backend
  deploys **per user, without root**, from `deploy_dotfiles` (phase 50 and
  ewe-setup both run it), not `/etc/xdg` as §6.1 first said. The PKGBUILD only adds
  `/usr/bin/ewe-portal` for `ewe-portal status`.
- `XDG_DESKTOP_PORTAL_DIR` (the frontend's test switch) also makes it read
  portals.conf from that folder only. tests/ewe-portal-test.sh relies on that.
- `qs ipc call <missing target>` prints "Target not found." and **exits 0**, so
  every verb returns a word ("ok", "open", "idle") and ewe-portal checks the
  word, never the exit code. (ewe-share-picker has the same blind spot: with
  no `picker` target it waits 300 s.)
- qt6ct builds its dialog helper with QPlatformThemeFactory, so
  `standard_dialogs=xdgdesktopportal` loads Qt's portal theme for dialogs only.
  Proved with PySide6: QFileDialog → portal → ewe-portal.
- `GTK_USE_PORTAL=1`: GtkFileChooserNative (GTK 3) → portal → ewe-portal.
  Proved with PyGObject.
- All five Tauri apps use only open/save/folder pick; `xdg-portal` brings rfd's
  tokio runtime by itself (plugin 2.7–2.8). All five `cargo check` clean.
- The nested harness runs a minimal Hyprland config, so the "underneath" cases
  could not be reproduced there; the overlay layer makes them impossible for
  ewe's picker anyway. They stay a real-device check for GTK fallbacks.

**Changed from the plan:**
- The shell answers on a private D-Bus method (`org.ewe.Portal1.Answer`), not a fifo.
  busctl returns `b false` for an answer the daemon refuses, so the picker can
  stay open and say why.
- `filepicker select <answer-json>` (not `<id> <json>`) answers the open
  request; `appchooser select <desktop id>`; both verbs are for tests.
- The card is centred on the focused screen (Dialog), not over the app's
  window.
- Thumbnails decode the picture itself, small and only for visible cells; the
  freedesktop cache and Space-to-preview are left for later.
- Sidebar rows are not Tab stops (Tab: list → file type → options); the path
  field and Alt+Up cover the keyboard.

**Tested:** `tests/ewe-portal-test.sh` (54 checks: helpers + the real frontend
on a private bus: pick, cancel, save several, open with, a refused answer,
no shell → GTK, shell lost → GTK). In the nested shell, on a private bus and
a 1920×1200 output:
- Open with a type filter, the app's options and a multi-select by keyboard;
- Save as with Replace;
- Select folder through a typed path;
- grid thumbnails;
- Recent;
- Esc;
- the app's Close;
- Open with;
- Ewe Light;
- the shell reloading in the middle of a pick, which went to the GTK dialog.

Not yet: a real-device pass (ewe Browser upload, Firefox, a Flatpak app, two
monitors, fullscreen parents).

