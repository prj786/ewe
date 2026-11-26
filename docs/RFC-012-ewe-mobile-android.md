# RFC-012 — ewe Mobile, both halves: the phone's folders, apps and screen on the desktop, and an ewe app for Android

*Status: **accepted** 2026-11-26 — the owner took all nine proposed answers
the same day (§9). Built and released that day: the Remote page fix (ewe
Mobile 0.1.1-beta, §3.1) and step A1, the phone in ewe Files (ewe-apps
0.5.0-beta, §4). **The same evening, the rest as one wave** (ewe 0.50.0-beta,
ewe.phone 1.2.0, ewe Mobile 0.2.0-beta, eep 0.4.1-beta, the Android app on
`ewe-connector-android` main): the §7 probes; A2–A4 (adb link, Screen in
scrcpy's window, Apps — open here or on the phone); B1–B3 (the fork, the ewe
face in Compose, the apps list with icons through `remotecommands`); plus
what the owner added that day — phone notifications as ewe cards (the app's
icon, an accent outline, a phone chip, inline reply), no KDE Connect window
anywhere, the phone in the dock, its apps in the launcher. The build plan
and its contracts: `ewe-mobile/docs/ECOSYSTEM.md`. Still open: B4 (not
needed), B5 (the release key), A3 step 2 (the screen inside the window).*
**Repos it touches:** `ewe-mobile` (new pages), `ewe-apps` (ewe Files),
a new `ewe-mobile-android` (the APK), `ewe` (package lists), `ewe-repo`.
**Number:** 009 is Remote, 010 eep, 011 the file picker; this is 012.

---

## 1. What was asked

The owner, 2026-11-26: research "how realistic it is to create new android
app using kde backend once again, but now apk. have similar layout as our
ewe-mobile plus new features like list of installed apps on the mobile,
displaying directory in ewe files as mobile integration. even more if i can
make run android installed apps in ewe, or moreover from ewe mobile display
android screen with casting. plan those".

That is five wishes. They do not all need the same thing, and that is the
main finding.

## 2. The short answer

| Wish | Realistic? | How | What the phone needs | Size |
|---|---|---|---|---|
| The phone's folders in ewe Files | **Yes, with the phone as it is today** | KDE Connect's SFTP + `sshfs`, a phone entry in ewe Files' sidebar | the stock KDE Connect app | S |
| The phone's screen in ewe | **Yes** | scrcpy over Wi-Fi debugging — its own window first, inside ewe Mobile later | Developer options → Wireless debugging, paired once | S, then L |
| Run an app that is on the phone as a window in ewe | **Yes, with the same price** — and **not possible without it** | scrcpy: a virtual display per app | the same | S–M |
| The list of installed apps | **Yes**, two ways | scrcpy `--list-apps` now; from our own app later (with icons) | debugging, or our app | S / M |
| An ewe app for Android, "KDE Connect + more" | **Yes — as a fork of the KDE Connect app**, not from nothing | fork (GPL), our face on it, new features through two doors the stock daemon already has | installing our APK | M to start, L for the full face |

S is a day or two of sessions, M about a week, L several weeks, XL months.
They are estimates.

Three things follow:

1. **Four of the five wishes need no Android app at all.** They need the
   desktop side built, and — for screen and apps — the phone's developer
   switch. So the desktop goes first (Track A, §4), the APK second (Track B, §5).
2. **Running the phone's apps on the desktop is closed to any normal Android
   app, ours included.** Android lets only the shell user or a system app put
   other apps on a virtual display. The debugging link is the only door on a
   stock Pixel; what our own app can do is hold that door open more
   comfortably (§5, B4).
3. **Writing the Android app from nothing is the wrong size.** The link to
   the daemon is two or three thousand lines; the thirty thousand that make
   KDE Connect useful — SMS and MMS, notification replies, the SFTP server,
   contacts, calls, the keyboard, the accessibility service — are what ewe
   Mobile already shows, and a rewrite would have to earn every one of them
   again.

## 3. What was checked

Checked 2026-11-26 on the owner's machine (kdeconnect 26.08.3, webkit2gtk-4.1
2.54.3, Linux 7.3.5-arch1, a paired Pixel 10 Pro XL) and in the sources
named in §10. "Unverified" means nobody confirmed it in a primary source or
on the phone.

### 3.1 The Remote page, and why it looked dead

Not part of the plan, but the same ground:

- The phone takes a pointer and keys only once **KDE Connect is an
  accessibility service** on it. Until then it drops both without a word.
  The owner's phone had it off (`remoteState` false while in reach), and the
  page told people to switch the phone's keyboard instead — the instructions
  for an older KDE Connect.
- The wheel never turned a page: the phone adds `dy` up and scrolls one
  screenful past 500; the page sent about 28 a notch, and the wrong way.
- `sendKeyPress` gained an argument in 26.08 (`super`, before `sendAck`).
- Paste could not be relied on: the box was not a real text field, and
  WebKitGTK hands a `paste` event no text for a pasted selection (measured).

Fixed in ewe Mobile 0.1.1-beta, with the phone's own Back / Home / Recents,
tap-hold-swipe, and the phone's acknowledgement of each key used as the only
honest sign that typing works. Tested against a stand-in daemon on a private
bus and, for the page itself, with real pointer and key events in WebKitGTK
under a headless compositor. **Not tested on a phone that accepts input** —
the owner's has to be switched on first.

### 3.2 The protocol, and what the stock daemon lets a new app do

- KDE Connect's protocol is at **version 8**; the code is the real spec
  (`kdeconnect-meta/protocol.md` is close; Valent's page still describes 7).
  kdeconnect 26.12 drops version 7 peers.
- `kdeconnectd` **throws away any packet type no plugin of its own
  declares**, will not send a type the other side did not announce, has no
  way to send or see a raw packet over D-Bus, and **cannot load a plugin
  built outside its own tree** — no headers are installed, upstream closed
  the request (KDE bug 361430), and the library's name changes with every
  release.
- Two doors are open all the same, with **no change on the desktop**:
  - **`remotecommands`.** A phone that announces `kdeconnect.runcommand` can
    hand the desktop a `commandList` — any JSON, kept as it came, readable as
    the `commands` property with a change signal — and the desktop can send
    back `triggerCommand(<any string>)`. That is a two-way control channel.
    "The apps I have" and "open this one" fit what it was made to mean.
  - **`virtualmonitor.request`**, and the way `sftp` works: the paired link
    hands over an address, a port and a secret, and the real traffic runs
    beside it. That is the precedent for a side channel of our own (icons, a
    stream), pinned to the certificates the pairing already exchanged.
- Nothing in KDE Connect, on either side, lists or launches the phone's apps
  today.

### 3.3 Android in late 2026

Android 17 (API 37) is the current release. For an app like this one,
installed from outside the Play Store:

- **Restricted settings.** Accessibility, notification access, "display over
  other apps" and the SMS permissions are greyed out for an APK that came
  from a browser, until the person opens App info → ⋮ → "Allow restricted
  settings". Installs over `adb` are believed to be outside this (unverified).
- **Local network** is its own permission from Android 17 for apps that
  target it (`ACCESS_LOCAL_NETWORK`); without it the link just times out.
- **Starting an app from the background** needs a reason Android accepts: an
  accessibility service that is switched on, "display over other apps", or a
  companion-device association. Otherwise: a notification to tap.
- **One-time codes** are hidden from notification listeners (since 15) and
  SMS codes are held back three hours for apps targeting 17 — unless the app
  has a companion-device association. KDE Connect has none and gets them
  redacted; ours could do better.
- **Developer verification.** Enforced since 2026-09-30 for installs from
  seven stores in four countries; Google says the rollout to everything else
  "begins in January 2027". After that an unregistered APK installs only
  through `adb`, or after the person switches on an "advanced flow" with a
  one-day wait. Registering is $25 and a government ID; a free "limited
  distribution" tier has a device cap (two readings of Google's guide say 20
  and 50 — check before relying on it). **`adb install` is exempt.**
- **Play Protect** blocks sideloaded apps that ask for SMS, notification
  access or accessibility in a list of countries, and has flagged KDE
  Connect's own F-Droid build elsewhere.

### 3.4 scrcpy and the debugging link

- **scrcpy 5.0.1** (2026-10-08, Apache-2.0) is in Arch `extra` and brings
  `android-tools`. It mirrors the screen at 35–70 ms (its own claim), with
  sound, clipboard both ways, and a real keyboard and mouse (`uhid`).
- `--list-apps` lists what is installed. `--new-display --flex-display
  --no-vd-system-decorations --start-app=<package>` opens one app on a
  virtual display of its own, in its own window that resizes the app.
- **Known trouble:** on Android 17 the virtual display's *launcher* does not
  open apps (scrcpy #7048, #7125, fix not merged); starting an app directly
  — what `--start-app` does — is reported to work. Windows marked secure
  (banking, DRM video) come out black. An app already open on the phone
  stays there unless it is stopped first.
- **Wireless debugging** (Android 11+) is paired once with a six-digit code
  and found by mDNS afterwards. On Android 11–16 it switches itself off when
  Wi-Fi drops, on another access point of the same network, and after a
  reboot. **Android 17 brings it back by itself on a network marked trusted**
  ("adb Wi-Fi 2.0", needs adb 37 — Arch has it).
- It is developer mode: a paired computer can do anything the shell user
  can. Some banking apps refuse to run while it is on (said widely, not
  confirmed in a primary source).
- scrcpy's window **cannot be put inside another app's window**. A client of
  our own on scrcpy's server is proven (Tango, QtScrcpy, a Tauri one called
  Another), but the protocol between them is internal and changes with every
  version: one server jar is pinned and shipped.

### 3.5 Without debugging: what our own app could show

Screen capture through Android's own API (MediaProjection) works for a
normal app, with a consent dialog **every session**, a stop **every time the
phone locks** (since Android 15 QPR1), notifications and password fields
blanked, and control only through the accessibility service. It cannot run
an app on a second display at all. It is a fallback for a phone whose owner
will not switch on developer options, not the plan.

### 3.6 Showing a stream inside ewe Mobile's window (measured here)

In a bare WebKitGTK 2.54.3 webview: `VideoDecoder` (WebCodecs) is there and
decoded a 1080×2400, 60 fps H.264 stream, every frame. WebRTC is not built
in. Three catches: the decoder wants the `avcC` form, not scrcpy's raw one;
each frame shows one frame late; and **with `WEBKIT_DISABLE_DMABUF_RENDERER=1`
the web process crashes on `configure()`** — the variable
`dotfiles/hypr/start-hyprland.sh` sets on virtual machines and NVIDIA. So an
in-window screen needs scrcpy's own window as the fallback on those machines.

### 3.7 What is not an answer

- **Waydroid** runs Android on the computer — another Android, without the
  phone's apps, logins or data, x86 only unless proprietary translation
  layers are added. It answers a different question ("Android apps on ewe").
- **Casting to the computer** the way a phone casts to a TV: Google Cast
  wants a certified receiver, and a Pixel has no Miracast.

## 4. Track A — the desktop first, the phone as it is

### A1. The phone in ewe Files (S) — built, ewe-apps 0.5.0-beta

As built (`apps/files/src-tauri/src/phones.rs`): the row, Connect, the away
state and Disconnect as below; a phone that shares more than one folder is a
row per folder; and every mounted device — drives too — is now the first
crumb and the tab's title ("Pixel › DCIM"), since the mount's own path is
thirty-two hex digits long. Connect and Disconnect ran against the owner's
Pixel; a phone with an SD card, and the mount dropping while a folder is
open, were not tried.

ewe Files lists drives through GIO's volume monitor
(`apps/files/src-tauri/src/devices.rs`); a phone mounted by KDE Connect is
not among them (the mount is under `$XDG_RUNTIME_DIR`, which GIO hides). Add
a second source beside it: paired phones in reach that offer `sftp`, read
from `kdeconnectd` over the session bus (GIO's own D-Bus — no new crate, and
never starting the daemon: the same unique-name rule ewe Mobile uses).

- The phone is a row under Devices with the phone glyph. Opening it calls
  `mountAndWait`, then shows the folders `getDirectories` names (internal
  storage, an SD card). Eject calls `unmount`.
- Out of reach: the row stays, dimmed, as a place that is not there now.
- What it can show is what Android gives any app with all-files access:
  shared storage, not `Android/data`.
- ewe Mobile's Files page keeps its button; it opens the same place.

### A2. The debugging link, owned by ewe Mobile (part of M)

A page section "Screen and apps" that says what it costs before it asks:
developer options on the phone, and that a paired computer may do anything
on it.

- `scrcpy` and `android-tools` are **optional** dependencies of `ewe-mobile`
  (the Package Diet); without them the section offers them through Komble.
- Pairing: the phone shows a six-digit code under Developer options →
  Wireless debugging → Pair with code; ewe Mobile finds the phone by mDNS
  and asks for the six digits, nothing else. After that it connects by
  itself whenever the phone offers the service.
- ewe Mobile keeps nothing resident: an `adb` server it started is stopped
  when the window closes. (A Rust ADB client would need no server at all;
  the crates are young — later.)
- Secrets: adb's key is adb's (`~/.android/adbkey`), never in `ewe.conf`
  (rule 2).

### A3. Screen (S for the first step, L for the second)

1. **scrcpy's own window**, started from a Screen page: Hyprland tiles it
   beside ewe Mobile. Honest about what it is; works the day `scrcpy` is
   installed.
2. **Inside the window**, later and only if the first step proves the
   feature is used: a Rust reader on a pinned scrcpy server, frames to
   WebCodecs on a canvas, input back over scrcpy's control socket. With the
   catches of §3.6 and the scrcpy window kept as the fallback.

Public page id: `screen`.

### A4. Apps (M with A2 and A3)

An Apps page: the list from `scrcpy --list-apps`, search, and two actions on
each app —

- **Open here**: its own window on the desktop (`--new-display
  --flex-display --no-vd-system-decorations --start-app`).
- **Open on the phone**: start it on the phone's own screen.

No icons until our own app supplies them (B3): a letter on a tile, as
contacts without a photo have. Public page id: `apps`.

### A5. Remote, with the link up

With debugging connected the Remote page can stop steering KDE Connect's
blind pointer: scrcpy's keyboard and mouse are the real ones. And ewe Mobile
could switch KDE Connect's accessibility service on by itself instead of
sending the person through Android's settings (one `settings put` over adb;
unverified on Android 17 — §7, probe 6).

## 5. Track B — ewe Mobile for Android

### B1. A fork, kept close to upstream (S–M)

- Fork `kdeconnect-android` (1.37.3; Kotlin; licence "GPL-2.0-only OR
  GPL-3.0-only OR KDE-accepted"). New repo `ewe-mobile-android`,
  **GPL-3.0-only**, as `ewe-apps` already is. The desktop app stays MIT: two
  programs that talk over a socket are not one work.
- Upstream moves fast (586 commits in 2026). So its protocol and plugin code
  is **left where it is and untouched**; ours lives beside it — the look, the
  screens, the new plugins — and a rebase stays mechanical.
- On the wire it *is* KDE Connect. Stock `kdeconnectd` pairs with it; ewe
  Mobile on the desktop needs no change to keep working, and the stock app
  stays supported. What is new lights up only when the phone announces it.
- The application id and the signing key are decided **before the first
  build anyone else installs**: both are what developer verification
  registers, and a lost key means no updates, ever. Proposed id:
  `io.github.prj786.ewemobile`.
- CI builds the signed APK on a tag (the house's release workflow shape);
  the key is a repository secret with an offline copy.

### B2. The ewe face (M–L)

The same pages as the desktop window, seen from the phone's side: the
**Computer** at a glance (what is playing there, send the clipboard or a
file, ring it), **Media** (the computer's players and volume), **Remote**
(the phone as the computer's touchpad and keyboard), **Devices** (pairing),
and a **Setup** page that walks through every permission, knows which ones
Android has greyed out, and opens the right settings screen for each.

- The design tokens become a Compose theme generated from `ewe/design`, held
  to the source by a check, like every other copy.
- Open question for this part: the phone as the computer's touchpad does not
  work on Hyprland today — kdeconnectd logs "Failed to create keymap" when
  the phone connects, and its Wayland input goes through a portal
  (RemoteDesktop) that xdg-desktop-portal-hyprland is not known to provide
  (unverified; not traced). That is a desktop fix of its own, not this RFC.

### B3. Apps, from the phone itself (M)

A plugin in the fork that publishes the launchable apps through the
`remotecommands` door of §3.2 — one entry per package, its name beside it —
and starts one when the desktop triggers it. Icons travel on a side channel
(the SFTP server the app already runs, as read-only files, is the cheapest;
decided in the build). On the desktop, ewe Mobile's Apps page reads the
`commands` property and gains icons, and "Open on the phone" works **without
debugging**. "Open here" still needs A2 — that is Android's rule, not ours.

Starting an app from the background needs one of the reasons in §3.3; the
Setup page asks for it. Without one, the phone shows a notification to tap.

### B4. Holding the door (only if §7 says so)

After one grant over the first debugging link (`WRITE_SECURE_SETTINGS`), our
app can switch wireless debugging on when the desktop asks, and say which
port. Shizuku does exactly this. Android 17 already brings the link back on
a trusted network, so this is built only if the probes show it is needed.

### B5. Getting it onto phones

1. **From ewe Mobile, over the debugging link** (`adb install`): outside
   developer verification, believed outside restricted settings, and the
   same link can grant the app its permissions in one go. The desktop sets
   the phone up. This is the main path.
2. **The APK on GitHub releases**, with Obtainium for updates: meets
   restricted settings, Play Protect's blocks where they apply, and from
   2027 developer verification (§3.3).
3. **F-Droid** later: a GPL fork with no Google libraries qualifies.

The Android source has to be public the moment anyone else gets the APK
(GPL). ewe Mobile's own repo is private today; that is a separate switch.

## 6. Not doing, and why

- **A daemon of our own on the desktop.** It would replace 9,000 lines of
  core and 15,000 of plugins to gain one thing — packet types of our own —
  which §3.2's two doors already give.
- **A clean-room Android app.** Only worth it if GPL were unacceptable. It
  is not: ewe Files, Player and Viewer are GPL-3.0 already.
- **A kdeconnectd plugin shipped from `[ewe]`.** Possible as a shim built
  against one exact kdeconnect version, rebuilt on every update. Offering an
  "apps" packet upstream is the clean way and can run in parallel.
- **Screen capture by our own app** as the main path (§3.5), **Waydroid**
  and **cast receivers** (§3.7).

## 7. Half an hour with the phone, before any code

Nothing to build: `sudo pacman -S scrcpy`, switch on Wireless debugging,
pair, and see. Each row decides something.

| # | Try | It decides |
|---|---|---|
| 1 | `adb pair`, `adb connect`, `scrcpy` | does it run well on Hyprland; is the delay fine by eye |
| 2 | `scrcpy --list-apps` | the Apps list |
| 3 | `scrcpy --new-display=1280x800/160 --flex-display --no-vd-system-decorations --start-app=<package>` with a plain app, a Google app, a banking app | does "Open here" work on this phone's Android; which apps come out black |
| 4 | leave the Wi-Fi and come back; reboot the phone | does the link return by itself — if not, B4 is needed |
| 5 | does the banking app still open with debugging on | whether Q2 below is a yes the owner can live with |
| 6 | `adb shell settings put secure enabled_accessibility_services org.kde.kdeconnect_tp/org.kde.kdeconnect.KdeConnectAccessibilityService`, then `accessibility_enabled 1` | can ewe Mobile switch the Remote page on by itself |
| 7 | mount the storage, copy a large file, let the phone sleep | how the Files row should behave when the link drops |

Rows 1–3 pass: Track A as written. Row 3 fails: Apps lists and opens on the
phone only, until scrcpy catches up with Android 17.

## 8. Order of work

0. The probes (§7).
1. **A1** — the phone in ewe Files. Independent of everything else.
   **Done** (ewe-apps 0.5.0-beta), ahead of the probes it does not need.
2. **A2 + A3 step 1 + A4** — the link, the screen in scrcpy's window, the
   apps as windows. One wave in `ewe-mobile`.
3. **B1** — the fork builds, pairs, installs from ewe Mobile.
4. **B3** — apps and icons from the phone.
5. **B2** — the ewe face, screen by screen.
6. **A3 step 2**, **B4** — only if living with the above asks for them.

## 9. The nine questions, as answered

The owner took every proposed answer on 2026-11-26. They stand as written.

1. **Fork or clean room?** — Fork, GPL-3.0-only, in `ewe-mobile-android`.
2. **Is developer mode on the phone an acceptable price for Screen and
   Apps?** — Yes, opt-in, with the cost said on the page before it is asked.
3. **Screen in scrcpy's own window first?** — Yes. Inside ewe Mobile's
   window only after the first step has been lived with.
4. **`scrcpy` and `android-tools`: dependencies or optional?** — Optional,
   offered through Komble from the page.
5. **The Android app's name and id?** — "ewe Mobile",
   `io.github.prj786.ewemobile`. Fixed before the first shared build.
6. **Developer verification: register (ID and $25), limited distribution, or
   adb only?** — adb from ewe Mobile as the main path, limited distribution
   for the beta, and the registration decided before going public. The
   owner's call: it is their identity.
7. **Apps through `remotecommands`, or wait for an upstream packet?** —
   `remotecommands` now; offer the packet upstream alongside.
8. **Does `ewe-mobile` go public first?** — The Android source must be
   public once the APK is shared; the desktop app going public is what puts
   it in `[ewe]`. Proposed: both together, with B1.
9. **The phone as the computer's touchpad on Hyprland** — its own item, not
   this RFC.

## 10. Sources

Read directly on 2026-11-26 unless marked.

- **This machine:** `busctl --user introspect org.kde.kdeconnect …` with the
  phone in reach; kdeconnect `v26.08.3` sources
  (`plugins/remotecontrol`, `remotekeyboard`, `remotecommands`,
  `virtualmonitor`, `sftp/mounter.cpp`, `core/device.cpp`,
  `core/pluginloader.cpp`, `core/backends/lan/`); kdeconnect-android
  `v1.37.3` and master (`plugins/mousereceiver`, `remotekeyboard`,
  `remotekeyboardime`, `KdeConnectAccessibilityService.kt`, `plugins/sftp`,
  `build.gradle.kts`); a WebKitGTK decode probe under headless `cage`.
- **Protocol:** <https://invent.kde.org/network/kdeconnect-meta/-/blob/master/protocol.md> ·
  <https://kde.org/info/security/advisory-20251128-1.txt> ·
  <https://bugs.kde.org/show_bug.cgi?id=361430>
- **Android:** <https://developer.android.com/privacy-and-security/local-network-permission> ·
  <https://developer.android.com/guide/components/activities/background-starts> ·
  <https://support.google.com/android/answer/12623953> (restricted settings) ·
  <https://developer.android.com/developer-verification/guides/faq> ·
  <https://developer.android.com/blog/posts/android-developer-verification-2027> ·
  <https://developer.android.com/media/grow/media-projection> ·
  <https://source.android.com/docs/core/permissions/app-streaming>
- **scrcpy and adb:** <https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1> ·
  <https://github.com/Genymobile/scrcpy/blob/master/doc/virtual-display.md> ·
  <https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md> ·
  scrcpy issues 7048, 7125 ·
  <https://developer.android.com/tools/adb#wireless-android11-command-line> ·
  <https://android-developers.googleblog.com/2026/09/wireless-debugging-adb-wifi-2.html> ·
  <https://github.com/RikkaApps/Shizuku>
- **WebKitGTK:** `Source/cmake/OptionsGTK.cmake` at `webkitgtk-2.54.3`
  (WebCodecs on, WebRTC off) · <https://bugs.webkit.org/show_bug.cgi?id=274711>
- **Waydroid:** <https://docs.waydro.id/> · <https://wiki.archlinux.org/title/Waydroid>

**Unverified, and it matters:** that `adb install` escapes restricted
settings; that the accessibility service can be switched on over adb on
Android 17; that banking apps refuse to run with debugging on; the device
cap of limited distribution; what `--start-app` does with an app already
open; the RemoteDesktop portal gap on Hyprland. §7 settles most of them.
