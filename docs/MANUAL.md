# The ewe manual

Everything that used to live in the README, for people who want the deep dive.
The [README](../README.md) covers installing and the quick tour; this covers how
it works and what to expect. (A proper website will eventually replace this.)

## Status & versioning

**Beta — `0.5.0-beta`.** Usable and daily-drivable, but expect rough edges and
breaking changes between versions. Tested on a minimal Arch install in a
QEMU/KVM VM and on Intel Lunar Lake hardware.

Versioning is **semver** (`MAJOR.MINOR.PATCH`) with an `-alpha`/`-beta`
pre-release suffix until the first stable cut. The canonical version lives in
the repo-root **`VERSION`** file; the shell mirrors it in
`dotfiles/quickshell/Globals.qml` (`Globals.version`, shown in the Settings
sidebar). Releases are git tags (`vX.Y.Z`) built by `release.sh`, which produces
the `ewe-<version>.tar.zst` artefact that `get.sh` installs.

> **Arch only.** Package install assumes `pacman` + the **AUR**. Arch
> derivatives (EndeavourOS, CachyOS, Garuda, Manjaro) should work. Artix
> (systemd-free) is detected but the service-enable phases are skipped — wire
> the equivalents into your init manually.

## Installing, in detail

```sh
bash install.sh              # prompts before each change
bash install.sh --dry-run    # show everything it would do, change nothing
bash install.sh --yes        # unattended
bash install.sh --check-only # just run the verification checklist
bash install.sh --gaming     # also install the optional gaming stack (Steam, …)
bash install.sh --dev        # also install the front-end dev toolchain (mise/Node, …)
```

The default install is lean: **no gaming and no dev packages** unless you ask.
`--gaming` opts in to Steam, gamescope, gamemode and mangohud (and only then are
[multilib] + the 32-bit GPU drivers enabled); `--dev` opts in to the front-end
dev toolchain (git-delta, lazygit, gh, mise + the Node/LSP stack, ripgrep, fd,
fzf, bat, cmake, meson). A plain `bash install.sh` asks once for each,
interactively; `--yes` skips both. Flags combine.

Run it as your **normal user** (not root) — the AUR helper and `makepkg` refuse
root, and the script uses `sudo` only where it must.

**Updating** — for tarball installs (the `get.sh` one-liner), just re-run the
one-liner: it refreshes `~/.local/share/ewe` in place and re-runs the installer.
For git clones, `./update.sh` pulls, re-runs the installer unattended, and
restarts the shell. Either way the repo tree is the single source of truth and
one command converges the machine onto it.

The installer is fully **re-runnable**: package installs are skipped if already
present, dotfiles are a symlink farm (re-linking is a no-op), system files in
`/etc` are (re)installed idempotently, and a package that isn't in the repos is
**warned and skipped** rather than aborting the run — a single missing package
never blocks the rest of the install.

### Phases

| Phase | Does |
|------|------|
| 00 preflight | tool/network/disk checks; announces the backup policy |
| 10 repos | bootstraps **paru**; enables **[multilib]** only with `--gaming` |
| 20 packages | installs `packages/common.list` (pacman) + `packages/aur.list` (AUR); `packages/gaming.list` only with `--gaming`, `packages/dev.list` only with `--dev` |
| 30 services | pipewire/NM/bluetooth/ppd; installs **greetd** + the themed greeter (ReGreet fallback) + the Wayland session entry |
| 35 bootsplash | **Plymouth** boot splash: installs the theme, adds the `plymouth` initramfs hook, and adds `quiet splash …` to the kernel cmdline (systemd-boot/GRUB/UKI, auto-detected + backed up) so no boot text ever hits the screen |
| 37 cpu microcode | detects the CPU and installs the matching **`intel-ucode`** / **`amd-ucode`**, then wires the early-boot microcode initrd into the bootloader. Skipped in a VM |
| 40 gpu | per-vendor Vulkan + VAAPI drivers for the detected GPU (Intel `xe` DPMS guard, NVIDIA suspend fix, AMD); mesa-only in a VM |
| 50 dotfiles | symlinks `~/.config/{hypr,quickshell,zed,kitty,oh-my-posh,mise}` (backing up any existing), installs the session target |
| 60 userconfig | default apps (**Zed** as editor, micro for `$EDITOR`), **mise** Node toolchain, zram (laptops) |
| 90 postcheck | green/red verification checklist |

Everything routes through one `run()`/`sudo_run()` choke point, so `--dry-run`
is genuinely safe and the whole thing is re-runnable.

### Packages

`packages/patched/<name>/` holds an official package rebuilt with upstream
fixes the repos don't carry yet (Arch's PKGBUILD, `pkgrel` N.1, the patches,
a header saying why). Phase 20 builds and installs it only while the repos
still offer that exact version, so it retires itself.

- **`packages/common.list`** — official-repo packages (real Arch names),
  installed with `pacman -S --needed`. Grouped: core session, greeter, audio,
  network, bluetooth, power, terminals, **GTK utility apps** (Nemo, Engrampa,
  imv, Zathura, mpv), browser, utilities, theming + fonts, `git`, core GPU
  userspace (mesa), tuning, build deps.
- **`packages/aur.list`** — AUR packages (built via paru): just
  `gpu-screen-recorder`. Kept deliberately short.
- **`packages/gaming.list`** — **optional, off by default.** Steam, gamescope,
  gamemode, mangohud + the 32-bit graphics libs. Installed only with
  `--gaming`, which is also what enables [multilib] and the lib32 GPU drivers.
- **`packages/dev.list`** — **optional, off by default.** The front-end dev
  toolchain. A normal install ships just `git`.
- **GPU/Vulkan drivers** are *not* in the lists — phase 40 installs the right
  set for the detected vendor; the 32-bit ones only with `--gaming`.

## Why traditional GTK apps (not Qt/KDE, not libadwaita)

The shipped first-party apps are **traditional GTK**: **Nemo** (file manager),
**Engrampa** (archives), **imv** (images), **Zathura** (PDF/docs), **mpv**
(video). These use a normal menubar/toolbar + server-side decorations, so under
Hyprland — which draws **no titlebar**, just the accent border — they come up
clean and fully borderless. The "GTK forces an unhideable headerbar" rule only
applies to **GNOME/libadwaita** apps (Nautilus, GNOME Calendar, Evince);
ordinary GTK apps don't, which is why the no-titlebar aesthetic *and* GTK can
coexist.

Going all-GTK also fixes default-app management: **one `~/.config/mimeapps.list`**
is the single source of truth, read natively by **GIO** — "Open With" always
sees your installed apps, with no KDE `ksycoca` cache to rebuild. Manage it from
**Settings → Default Apps**. Right-click **Compress… / Extract Here** in Nemo
ship as `system/nemo-actions/*.nemo_action` (calling engrampa).

**Appearance** (dark + accent — ewe is dark-only by decision; there is no light
mode) is applied by `dotfiles/quickshell/scripts/colorscheme.sh` and changed
live in **Settings → Theme**:

- **GTK** (primary) — gsettings + `gtk-3.0/4.0/settings.ini` (adw-gtk3[-dark]);
  accent changes recolour GTK apps live.
- **Qt** — `qt6ct`/`qt5ct` write a dark **Fusion** palette
  (`QT_QPA_PLATFORMTHEME=qt6ct`) so any stray Qt app stays dark. A `kdeglobals`
  fallback covers any KDE app added later. No `plasma-integration`.
- **Icons** — **Reversal**, auto-matched to the accent by hue.
- **Cursor** — **Mocu** (`mocu-xcursor`), forced via `XCURSOR_THEME`,
  `~/.icons/default`, GTK, gsettings and qt6ct so it never flips between
  toolkits.

## Safety model

- **Never clobbers configs.** An existing `~/.config/hypr` (etc.) is moved to
  `…​.bak.<timestamp>` before the symlink is created; `uninstall.sh` restores it.
- **Symlink farm, not copy** — re-running re-links (no-op); `uninstall.sh`
  unlinks and restores the newest backup. Packages are left installed (use
  `--purge` to also disable the display manager).
- The single most important step is the **`hyprland-session.target`** user unit
  (`BindsTo=graphical-session.target`) — it activates `xdg-desktop-portal` on a
  non-uwsm session. Without it, screen sharing, file pickers, and app/URL
  handoff silently fail.
- **User-state files** (`user-theme.json`, `pinned-apps.json`,
  `generated/user.lua`, …) are gitignored; committed `*.default` templates seed
  them only when missing, so a fresh install has working defaults while your
  edits are never committed or clobbered.

## Google account (optional)

Settings → User can connect a Google account **natively** (OAuth 2.0
installed-app flow with PKCE + loopback redirect — no GNOME Online Accounts
needed). It powers three things: **calendar events** in the Quick Settings
calendar (dots + agenda + reminder notifications), **Gmail** (a bar envelope
with the real INBOX unread count, new-mail notifications, and a mail list in
the control centre that deep-links into Gmail — read-only) and **settings
sync** — one versioned bundle (theme, keyboard, dock, wallpaper, shortcuts,
screensaver, avatar shape, display profiles, plus your package *list*) stored
in Google Drive's hidden per-app `appDataFolder`. After a reinstall, sign in
and hit "Restore from cloud" to get your setup back; reinstalling packages
from the captured list is always a separate, opt-in command.

On a fresh install the **Welcome** flow walks through it: a *Connect to the
internet* step first (Wi-Fi is joined from the flow itself — sign-in and
the Drive restore both need a connection), then an *Updates* step, then the
one sign-in, then the restore offer. The Updates step exists because a
fresh install carries the package database of its install day, and Arch
mirrors drop superseded versions within days — so installing anything on
that database fails with 404s, and Komble refuses partial upgrades by
design. Welcome runs `checkupdates`, and if anything is waiting offers the
one safe move, a full `pacman -Syu` (one authentication prompt, progress in
the card), before the app restore can try to install a thing. *Later*
defers it to Komble → Updates. A machine that has never synced never uploads on its own:
its first backup is the explicit *Back up this machine* button (Welcome, or
Settings → User), so a fresh install can never overwrite the backup it is
about to restore. If the keyring or the browser misbehave, see
[Troubleshooting → Google sign-in](TROUBLESHOOTING.md#google-sign-in-no-keyring-prompt-keyring-not-showing-up-no-browser).

One-time setup (Google requires your own OAuth client for native apps):

1. [console.cloud.google.com](https://console.cloud.google.com) → new project →
   enable the **Google Calendar API**, **Google Drive API** and **Gmail API**.
2. *OAuth consent screen*: External. Then **publish the app to "In
   production"** (Audience → Publish). Don't leave it in *Testing*: with
   Calendar/Drive/Gmail scopes a Testing app issues refresh tokens that
   **expire after 7 days**, forcing a weekly re-login. Publishing an app for
   personal use needs **no Google verification** — you just click through an
   "unverified app" warning once during consent.
3. *Credentials* → **Create OAuth client ID** → type **Desktop app**.
4. Save the id/secret as `~/.config/quickshell/google-oauth.json`:
   `{ "client_id": "…apps.googleusercontent.com", "client_secret": "…" }`

That file is **gitignored**; a Desktop-app client secret is explicitly
non-confidential. The **refresh token** never touches a file — it lives in the
Secret Service keyring (`gnome-keyring`, via `secret-tool`). Scopes requested:
`openid email profile`, `calendar.readonly`, `drive.appdata`, `gmail.readonly`
(the shell can read your calendar, mail headers and its own hidden app folder —
nothing else; it can never send or delete anything). `gmail.readonly` is
Google's *restricted* tier — fine for a personal published-unverified client
via the warning clickthrough; if Google ever hard-blocks it, the shell simply
shows mail as unavailable while calendar and sync keep working. Sign out
revokes the token at Google and clears the keyring. Helper:
`dotfiles/quickshell/scripts/google-auth.py` (stdlib-only Python). Everything
degrades cleanly when signed out or offline.

## VPN

ewe ships the NetworkManager plugins for **OpenVPN** and **L2TP/IPsec**
(the corporate/ISP kind: server, username, password, pre-shared key);
WireGuard is native. Add a VPN in **Settings → Network → Add VPN** — an
L2TP one from its four facts, an OpenVPN or WireGuard one from its file —
or import from a terminal (`nmcli connection import type openvpn file
x.ovpn`). Then toggle it in the **Control Center → VPN** card. The first
connect asks for the credentials once, inline, and keeps them in the
profile (root-only, under `/etc/NetworkManager`); the one file records the
definition, never the secrets, so a restored machine asks once again.

## Phone (KDE Connect, optional)

The control centre has a **Mobile** card that pairs your Android phone through
**KDE Connect's daemon** (only the daemon — the UI is all ewe): device
discovery + pairing (both directions), phone battery in the bar, the phone's
notifications (read, dismiss, inline-reply), and **SMS** — full conversation
list and thread view with send, right in the control centre.

Setup: `kdeconnect` is in the package set (phase 20); install the KDE Connect
app on the phone ([F-Droid](https://f-droid.org/packages/org.kde.kdeconnect_tp/)
/ Play Store), put both devices on the same Wi-Fi, open the Mobile card and tap
**Pair** — accept on the phone, then grant the app's notification/SMS
permissions there. `kdeconnectd` is started by autostart and D-Bus-activated on
demand; the shell talks to it through
`dotfiles/quickshell/scripts/kdeconnect-bridge.py`. Pairing keys stay in
kdeconnectd; the shell only persists which notifications you've seen and the
chosen device. MMS bodies often aren't exposed over D-Bus — threads label them
instead of showing garbage.

## Cast to TV (screen mirroring)

The control centre has a **Cast** tile (also `Super+Shift+C`) that mirrors the
desktop to a smart TV. It runs **`gnome-network-displays`** (AUR, phase 20),
the one app that speaks both protocols a TV may offer, and captures the screen
through the xdg-desktop-portal ScreenCast — the Hyprland portal — so it works
fine outside GNOME:

- **Miracast** — Samsung "Screen Mirroring" (Tizen) and most Android TVs. Uses
  Wi-Fi Direct (P2P) through NetworkManager + wpa_supplicant, so the Wi-Fi card
  must support P2P (`iw list | grep -E 'P2P-client|P2P-GO'`). NetworkManager's
  **iwd** backend has no P2P — keep `wifi.backend=wpa_supplicant` (the default).
- **Chromecast** — Chromecast built-in / Google TV. Found over mDNS, which is
  why phase 30 enables **`avahi-daemon`**.

Turning the tile on launches the app: its window lists the TVs it can see, you
pick one, and the TV asks you to accept. Closing that window (or toggling the
tile off, which SIGTERMs the app so the session ends cleanly) stops the
mirror; the tile and the bar's screencast glyph follow the process, not the
other way round. The first toggle of a session runs
`hypr/scripts/cast-check.sh`, which toasts anything missing together with the
fix (`paru -S gnome-network-displays`, `sudo pacman -S iw`,
`sudo systemctl enable --now avahi-daemon`); a missing app is the only fatal
case — a Chromecast-only or Miracast-only setup still launches.

**Which screen?** When the app asks the portal for the picture, the portal
pops **ewe's own share picker** (`SharePicker.qml`) — every display as a
live thumbnail named by its model, every window with a live preview, or a
region — instead of xdg-desktop-portal-hyprland's stock white list of
connector names. It's wired through `hypr/xdph.conf`
(`screencopy:custom_picker_binary = /usr/local/bin/ewe-share-picker`, the
wrapper phase 30 installs from `system/bin/`); the wrapper asks the running
shell over `qs ipc call picker …` and falls back to `hyprland-share-picker`
when the shell is down, so screen sharing never silently breaks. The same
picker serves every portal ScreenCast — browser calls, OBS, recorders.

**When a connect fails**, the app shows one line and nothing else. The real
reason is in the system journal — NetworkManager drives the Wi-Fi Direct link
and wpa_supplicant does the handshake — so while casting the shell tails both
and toasts a translation: *TV found*, *link up*, or the failure with what to
do (e.g. "the TV never answered the handshake — open Source → Screen
Mirroring on the TV so it's listening, then pick it again"). The app's own
debug output is kept in `~/.local/state/ewe/cast.log`; for the raw story run
`journalctl -f -u NetworkManager -u wpa_supplicant` during an attempt.

**Why it needs a patched portal.** xdg-desktop-portal-hyprland 1.4.1 freezes
a screen share for good the first time the consumer returns a buffer late —
on the TV that's a static image, or a connect that drops after ~10 s. The
three upstream fixes (#422/#424/#425) landed after the release, so phase 20
builds **`xdg-desktop-portal-hyprland 1.4.1-1.1`** from `packages/patched/`
(Arch's PKGBUILD + the patches; it retires itself once the repos ship newer).
For quality, `gst-plugin-va` gives hardware H.264 (the app prefers it), and
phase 30 sets the Wi-Fi regulatory domain so Wi-Fi Direct may use 5 GHz —
see *Troubleshooting → Cast to TV*.

Expectations: Miracast works on most 2018+ Samsung sets but Samsung's
implementation is finicky (retry, keep the laptop close to the TV; a 5 GHz
Wi-Fi network — or no Wi-Fi at all while casting — avoids sharing a 2.4 GHz
channel with the mirror). Chromecast-with-Google-TV devices don't do Miracast
at all — `gnome-network-displays` uses its Chromecast path for them, which
needs the laptop and TV on the same network.

**Audio.** The mirror carries sound too: while casting, `cast-audio.sh` routes
the desktop's audio into the sink gnome-network-displays streams to the TV
(GND makes the sink but doesn't redirect audio itself), and puts your speakers
back when you stop. To keep sound on the laptop instead, pick your speaker
again in `pavucontrol` while casting.

**Streaming apps (Stremio, browsers) and their own "Cast" button.** That button
is the *app's* casting (Chromecast/DLNA), not ewe's — it hands the TV a stream
URL to fetch itself, and only works with a device that speaks that protocol
(Chromecast built-in / DLNA renderer). A Samsung/Miracast TV isn't one, so the
button pauses local playback and nothing appears on the TV. For those TVs, use
ewe's **Cast** tile to mirror the whole desktop, then play the video normally —
picture and sound both go over Miracast. (A real Chromecast/Google TV *does*
answer Stremio's cast, and also shows up under ewe's Chromecast path.)

## Repo layout

```
install.sh  uninstall.sh  update.sh  get.sh (curl bootstrap)  release.sh
VERSION (project semver)  VERSIONS (min tool versions)
lib/      log.sh detect.sh pkg.sh deploy.sh
packages/ common.list  aur.list  gaming.list  dev.list
phases/   00…90
dotfiles/ hypr/  quickshell/      ← the actual configs, symlinked into ~/.config
systemd/  hyprland-session.target ← the portal-activation fix
system/   greetd/ branding/ …     ← installed to /etc (+ the ewe logos)
templates/hyprland-de.desktop.in  ← rendered into the wayland-sessions dir
```

## Hardware notes: Intel Lunar Lake / Arc 140V

On Intel Lunar Lake (Arc 140V), the `xe` kernel driver has a DPMS-resume bug
that can strand a black screen, so the shipped `hypridle.conf` locks but
**never powers the panel off**. If the iGPU tears or hangs, logging in once
with `DE_SOFTWARE_RENDER=1` set falls back to software rendering (see
`dotfiles/hypr/start-hyprland.sh`). Hardware without this bug is unaffected and
can re-enable panel-off in `hypridle.conf`.

## Known limitations

Set expectations before you daily-drive it:

- **The screen never powers off on idle** (only locks) — a deliberate
  workaround for the Lunar Lake `xe` DPMS-resume bug above. Re-add a `dpms off`
  listener in `hypridle.conf` on hardware without the bug.
- **Idle behaviour, laptop on battery:** locks at 5 min, **suspends at 15 min**
  (only on battery — never on a desktop or while plugged in). Delete the second
  listener in `hypridle.conf` to disable.
- **Low battery is handled automatically:** a warning at 20% and 10%, and a
  **suspend at 5%** to protect unsaved work.
- **The shell auto-respawns.** Quickshell runs as a `Restart=on-failure`
  systemd user service, so a crash brings the bar/dock/lock back on its own.
  The lock uses the Wayland session-lock protocol, so outputs stay locked even
  if the shell dies while locked.
- **The session lock is a young component**, not battle-tested hyprlock. It
  works, but it's the youngest security-relevant piece — report anything off.
- **Multi-monitor hotplug is lightly tested.**
- **No input method (IME) yet** — CJK / complex-script input isn't wired.
- Real-hardware coverage is still thin. Issues and PRs welcome.

## Roadmap

Live on the [project board](https://github.com/users/prj786/projects/5) ·
[Issues](https://github.com/prj786/ewe/issues) ·
[Discussions](https://github.com/prj786/ewe/discussions).
