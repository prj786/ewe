# Troubleshooting

## Cast to TV: frozen picture, lag, or the TV drops after ~10 s

What the 2026-08-21 investigation found, in the order it bit:

1. **Capture freezes for good (static image on the TV, or the TV connects and
   drops ~10 s later because no frames ever arrive).** xdg-desktop-portal-
   hyprland 1.4.1 has a bug in its screencopy retry path: the first time the
   consumer (gnome-network-displays encoding 1080p in software) returns a
   PipeWire buffer late, the portal logs `Out of buffers` → `Retrying
   screencopy` → `tried scheduling on already scheduled cb` and then never
   asks the compositor for another frame. Upstream fixed it after the release
   (commits #422/#424/#425). ewe ships them as **`xdg-desktop-portal-hyprland
   1.4.1-1.1`** from `packages/patched/` (phase 20 builds it; it retires
   itself once the repos ship something newer). Check with
   `pacman -Q xdg-desktop-portal-hyprland` and
   `journalctl --user -u xdg-desktop-portal-hyprland | grep -c "Out of buffers"`.
   Measured: stock 1.4.1 delivered 7 frames to a slow consumer and froze;
   patched kept delivering at the consumer's pace indefinitely.
2. **Lag / stutter while it works.** Two causes, both fixable:
   - software x264 encoding — `gst-plugin-va` gives `vah264enc`, which
     gnome-network-displays prefers automatically (Intel iHD / AMD).
   - the Wi-Fi Direct link shares the channel of your Wi-Fi connection. On a
     2.4 GHz network that is a crowded 20 MHz channel for both. A fresh Arch
     also has no regulatory domain (`iw reg get` → `country 00`), which makes
     5 GHz receive-only, so Wi-Fi Direct can never use it: phase 30 installs
     `wireless-regdb` and sets the country from GeoIP. Then use a 5 GHz
     network, or disconnect Wi-Fi while casting.
3. **The TV drops on its own after a few minutes** (a working stream just
   stops; the journal shows `AP-STA-DISCONNECTED` from the TV then NM
   `peer-not-found`, and nothing else). The culprit is **Wi-Fi power saving**:
   the laptop is the Wi-Fi Direct group owner, and a radio that still power-saves
   its normal Wi-Fi link delivers the group's beacons and video late, so the TV
   gives up (measured 3.5 min on 2026-08-21). Phase 30 installs a NetworkManager
   dispatcher hook (`/etc/NetworkManager/dispatcher.d/50-ewe-cast-powersave`)
   that turns `power_save off` on the Wi-Fi interface while any `p2p-*`
   connection is up and back on after. Check it's there and, live,
   `iw dev wlan0 get power_save` should read `off` while casting.
4. **No sound on the TV (audio stays on the laptop).** gnome-network-displays
   makes a null sink (`gnome_network_displays_*`) and streams *its* monitor, but
   never moves your audio into it. ewe's `hypr/scripts/cast-audio.sh` (started by
   Cast.qml while casting) makes that sink the default and moves live streams
   onto it, restoring your speakers when casting stops. If sound doesn't follow,
   check `pactl get-default-sink` names the `gnome_network_displays` sink while
   casting; set it by hand in `pavucontrol` → Playback / Output Devices if not.
5. **"Connection failed" with nothing else.** The app is terse; the reason is
   in the journal. While casting, the shell tails NetworkManager +
   wpa_supplicant and toasts a translation (TV found · handshake timeout ·
   refused · connected-then-dropped). Raw: `journalctl -f -u NetworkManager -u
   wpa_supplicant`; the app's own debug trace is `~/.local/state/ewe/cast.log`.
   `supplicant-timeout` with no GO-negotiation lines = the TV wasn't listening
   (open Source → Screen Mirroring on it first).

Run `~/.config/hypr/scripts/cast-check.sh` any time — it checks all of the
above and prints the fix for each.

## Sign-in: no keyring prompt, "keyring not showing up"

The account credential — the Nextcloud app password (RFC-005), and Google's
refresh token when that optional client is configured — lives in the Secret
Service keyring (`gnome-keyring`), which PAM creates and unlocks with your
login password at the greeter. When that works you never see a prompt at all.

**The cause, found 2026-09-03.** Arch's systemd preset *enables*
`gnome-keyring-daemon.socket`. That unit socket-activates the daemon at login
with **no password**, takes `org.freedesktop.secrets` before
`pam_gnome_keyring` can hand its own daemon your login password, and then
restarts it mid-login. One unit produced every reported symptom at once: no
`login` keyring is ever created (so you meet a *"Choose password for new
keyring"* prompt for a **Default keyring** instead of a silent unlock),
several prompts stack up unanswered behind whatever is on screen, and the
first sign-in dies with `keyring-timeout`. In the journal:

```text
sign-in failed: keyring-timeout
Stopping GNOME Keyring daemon... / Started GNOME Keyring daemon.
```

four seconds apart, at login.

`install.sh` phase 30 masks both `gnome-keyring-daemon.socket` and
`gnome-keyring-daemon.service` under `/etc/systemd/user`, leaving PAM as the
only starter; `ewe-setup` applies the same mask at user level, so a machine
installed before this heals itself at the next login without root. D-Bus
activation is left alone on purpose — its `Exec` is
`gnome-keyring-daemon --start`, which attaches to the PAM-started daemon
instead of spawning a second, password-less one.

Check it:

```sh
systemctl --user is-enabled gnome-keyring-daemon.socket   # expect: masked
ls ~/.local/share/keyrings/login.keyring                  # expect: present
```

**You already have a "Default keyring".** The mask stops a new machine from
ever getting one, but it cannot re-key the one you have: that keyring was
created with a password PAM does not know, so it stays locked until you type
it. Clear it and let PAM start over:

```sh
ewe-auth keyring-reset      # or: mv ~/.local/share/keyrings{,.bak}
# log out and back in — PAM now creates login.keyring with your login
# password — then sign in again from ewe-sync.
```

The old files are kept in `~/.local/share/keyrings.bak.<timestamp>`.

**A prompt appears anyway.** Then it is a genuine request from some app, not
a stuck one — answer it with your **login password**. It is floated, centred
and kept small by a window rule (`dotfiles/hypr/hyprland.lua`; gcr's GTK
dialog has its own minimum width and will not shrink much past 400 px).
Before 0.9.16-2 the first-run Welcome overlay sat above every other window,
the keyring prompt included; Welcome now steps aside while a sign-in runs
and takes input only on its own card.

**The browser never opened** (no tab, "Waiting for the browser…"): the
helper now tries `xdg-open`, then the shipped browser by desktop id, then by
binary, and reports `browser-failed` instead of waiting five minutes. The
sign-in page's link is always available — **Open the sign-in page** /
**Copy the link** in Welcome and in ewe-sync — and is also written to
`$XDG_RUNTIME_DIR/ewe-auth-consent-url` for the length of the attempt.
Command-line tools that open a browser (`gh auth login`, Python's
`webbrowser`) use `$BROWSER`, which the session sets to `gio launch` of the
shipped browser's desktop entry: it returns immediately, where `xdg-open`
would block until the first browser window closes and leave the tool
hanging after the web side already said "authorized".

Diagnose from a terminal: `ewe-auth status` (`keyring_state` is one of
`ok` · `missing` · `locked` · `unavailable`) and `ewe-auth login` (its
stderr carries the `consent-url:` line; the JSON result names the exact
failure). `install.sh --check-only` prints the same keyring notes.

## The laptop hard-freezes (must force power-off)

A full freeze — pointer stuck, keyboard dead, REISUB does nothing — is almost
never the shell itself: Quickshell runs as a respawning user service and
Hyprland crashes back to the greeter. A machine that needs the power button is
a **kernel/driver-level** hang, and on this hardware (Intel Lunar Lake, Arc
140V on the `xe` driver) the GPU/display driver is the prime suspect. The same
platform already needed one workaround in `hyprland.lua` (the CPU-buffer
hardware cursor — see the comment there), and blur has been removed from the
config partly to lower constant GPU load.

### 1. Capture evidence (do this first, after the next freeze)

The installer now enables the **persistent journal** (`/var/log/journal`,
phase 30), so the frozen boot's log survives the forced power-off. After
rebooting:

```bash
journalctl -b -1 -p err --no-pager | tail -60   # errors from the frozen boot
journalctl -b -1 --no-pager | tail -120          # the very last lines before it died
```

What to look for:

| Signature in the log | Meaning |
|---|---|
| `xe … GPU HANG`, `GT reset`, `GuC`, `engine reset`, `wedged` | GPU hang — go to step 2 |
| `drm … flip_done timed out`, `Atomic commit`, `PSR` | display/panel path — go to step 2 (PSR) |
| `Out of memory: Killed process` | OOM, not a driver bug — close/limit the culprit, keep zram |
| `thermal`, `critical temperature` | overheating — check dust/fans, power profile |
| log just *stops* mid-line with nothing above | often PSR/display or firmware — step 2 still worth trying |

### 2. Likely fixes, in order

1. **Update kernel + firmware first.** Lunar Lake support in `xe` matures with
   every release; many freeze reports are fixed by a newer `linux` +
   `linux-firmware` (GuC/DMC firmware ships there). `sudo pacman -Syu`, reboot.

2. **Disable PSR (Panel Self Refresh).** The single most common cause of
   hard display freezes on Lunar Lake laptops. Test it for one boot by adding
   a kernel parameter (edit the line in the bootloader menu, or make it
   permanent in `/etc/kernel/cmdline` / your bootloader config):

   ```
   xe.enable_psr=0
   ```

   If the freezes stop, keep it (costs a little battery). A softer variant to
   try after that: `xe.enable_psr=1` (PSR1 only) or
   `xe.enable_psr2_sel_fetch=0`.

3. **If the log showed GuC/GT resets** rather than PSR/flip lines, also try
   `xe.enable_dc=0` (display C-states off) for a boot.

4. **Make silent freezes logged freezes.** CachyOS boots with `nowatchdog` on
   the kernel command line, which disables hard-lockup detection — a locked-up
   kernel dies without a trace. Removing `nowatchdog` (and adding
   `softlockup_panic=0`) for a few boots lets the watchdog print a backtrace
   to the journal when the next freeze hits, turning "log just stops" into an
   actual culprit line.

5. **Still freezing with no log at all?** Test whether it's suspend-related
   (`s2idle` wake-ups): does it only happen after the lid was closed or the
   machine idled? Then look at `journalctl -b -1 | grep -i -E "suspend|resume|s2idle"`.

Report what `journalctl -b -1` showed when asking for help — with the
persistent journal in place there is finally something to read.
