# Safe — an ewe plugin

`ewe.safe` — first-party, opt-in like every ewe plugin (Komble → Plugins).
Safe, ewe's password manager ([prj786/ewe-safe](https://github.com/prj786/ewe-safe)),
on your desktop:

- **A lock in the bar** (inside the Quick settings pill): closed while the
  safe is locked, open while it's unlocked, with a dot when something needs
  you — a sync error, an older copy from your server, a master password
  changed on another computer, Safe's service not running. Click it for
  Quick Access.
- **Quick Access — `Super+Shift+P`**: every item, one search away.
  `Enter` copies the password, `Ctrl+C` the username, `Ctrl+O` the
  one-time code (shown with its countdown), `Ctrl+Enter` opens the item in
  Safe, `Ctrl+N` adds a login, `Ctrl+L` locks. Reopen it within two minutes
  and your search is still there (username, paste, back for the password).
- **A Quick settings tile**: tap to lock, or to unlock; the chevron opens
  the Safe window.

To fill a login into the app in front of you, use `Super+P` (the Passwords
plugin, with Safe as its provider). Quick Access is for everything else.

## What it never does

- It never asks for the master password. Unlocking runs
  `ewe-safe unlock --ask`, which opens Safe's own prompt.
- It never sees a password. Copies are the daemon's (`ewe-safe copy`): the
  clipboard history skips them and they're cleared after a while. The only
  secret it shows is a one-time code, while its item is selected.
- It never runs a shell — every call is argv.

## How it works

`SafeState.qml` (a singleton the three entry points share) follows Safe
through `ewe-safe watch`, one JSON line per event
([PROTOCOL.md](https://github.com/prj786/ewe-safe/blob/main/docs/PROTOCOL.md)).
When the bridge isn't running, a watchdog checks for `ewe-safe` with a
growing pause (up to 30 s), so installing Safe later is picked up without a
restart. `logic.js` is the plain logic, tested in a bare QML engine.

    qs ipc call ewe.safe toggle | open | hide | lock | unlock | status

Needs `ewe-safe` (declared in `requires`). `Super+Shift+P` was free in ewe;
`Ctrl+Shift+Space` was not used because 1Password's Quick Access and
JetBrains IDEs already take it.

## Tests

    ./test.sh        # the manifest, logic.js (qmltestrunner), the house rules, the fake

`tests/fake-ewe-safe` stands in for `ewe-safe` (state in `$FAKE_SAFE_DIR`)
in the tests and in the nested harness.
