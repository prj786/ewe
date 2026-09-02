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

## Google sign-in: no keyring prompt, "keyring not showing up", no browser

What the first bare-metal install (2026-09-02) taught, and what 0.9.16-2
changed. The refresh token lives in the Secret Service keyring
(`gnome-keyring`), which PAM is supposed to create and unlock with your
login password at the greeter. Three things can go wrong:

1. **No prompt ever appears / the sign-in seems to hang.** Before 0.9.16-2
   the first-run Welcome overlay sat above every other window — including
   the keyring prompt and the browser it had just opened — and the sign-in
   helper killed its own keyring prompt after 10 s. Now Welcome steps aside
   while a sign-in runs, and the helper waits as long as the login does.
   If you are on an older shell: press **Esc** on Welcome (it can be
   reopened with `qs ipc call welcome toggle`), then sign in from
   Settings → User.
2. **A "Choose password for new keyring" or "Unlock keyring" prompt
   appears.** PAM did not create/unlock a login keyring for this account.
   Answer it with your **login password** — that is what lets it unlock by
   itself at every later login. Check the PAM side with
   `grep gkr-pam <(journalctl -b _COMM=greetd)` (expected: *"gnome-keyring-daemon
   started properly and unlocked keyring"*) and `cat /etc/pam.d/greetd`
   (it must carry the `pam_gnome_keyring.so` auth + session lines from
   `system/pam.d/greetd`; `install.sh` phase 30 re-installs it).
3. **Wrong keyring password, or the shell says "signed out" at every
   login.** A keyring created with a password other than your login
   password stays locked until you type it, and "Unlock keyring" rejects
   the password you know. Replace it: **Reset the keyring** in Welcome or
   Settings → User (it appears whenever the keyring is locked or refused
   the token), then **Log out now**. PAM recreates the login keyring with
   your login password at the next login; sign in again afterwards. The
   old files are kept in `~/.local/share/keyrings.bak.<timestamp>`. The
   same thing by hand:

   ```sh
   ewe-auth keyring-reset      # or: mv ~/.local/share/keyrings{,.bak}
   # log out and back in, then Settings → User → Sign in with Google
   ```

**The browser never opened** (no tab, "Waiting for the browser…"): the
helper now tries `xdg-open`, then the shipped browser by desktop id, then by
binary, and reports `browser-failed` instead of waiting five minutes. The
sign-in page's link is always available — **Open the sign-in page** /
**Copy the link** in Welcome and in Settings → User — and is also written to
`$XDG_RUNTIME_DIR/ewe-auth-consent-url` for the length of the attempt.

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
