# Troubleshooting

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
