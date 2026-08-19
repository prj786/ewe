# Security policy

ewe is **alpha** software and ships security-relevant components — a polkit
authentication agent (`Auth.qml`), a Wayland session lock (`Lock.qml`), and
gnome-keyring PAM integration. Treat it accordingly until it stabilises.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem. Use GitHub's private
reporting instead:

1. Go to the repo's **Security** tab → **Report a vulnerability**
   (Private Vulnerability Reporting), or
2. open a **draft security advisory**.

Include what you'd put in a bug report: affected component, repro, impact, and your
environment (GPU/driver, distro, ewe version).

## Scope

Most interesting to us: anything that lets the **lock screen be bypassed**, the
**polkit agent be spoofed or its password captured**, the **keyring be unlocked
unexpectedly**, or privilege escalation through the install scripts. The installer
uses `sudo` only at explicit `sudo_run` points and never passes passwords on the
command line (the App Store uses a 0700 `SUDO_ASKPASS` helper under
`$XDG_RUNTIME_DIR`); regressions there are in scope.
