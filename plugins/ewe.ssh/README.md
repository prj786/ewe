# SSH — an ewe plugin

`ewe.ssh` — first-party, shipped inside the ewe payload, installed on request.

Your hosts from `~/.ssh/config` (and `~/.ssh/config.d/*`) in Quick settings.
A tile on the home grid says how many hosts you have, or "Tunnel on"; its
page lists them:

- **click a host** — a terminal (kitty) already ssh'd into it;
- **globe** — bring up a background SOCKS5 tunnel to the host
  (`ssh -f -N -D $SOCKS_PORT`, key or agent sign-in only) and run the browse
  script you saved for that host, typically a browser pointed at
  `socks5://127.0.0.1:$SOCKS_PORT`; the first click opens a paste-once
  editor for the script (`SSH_HOST` and `SOCKS_PORT`, default 1080, are set);
- **pencil** — edit or delete the saved script;
- **stop mark** — stop the host's tunnel.

A square-terminal glyph sits in the bar's Quick settings pill while a tunnel
is up.

## Install

Komble → Plugins, or:

    ewe-plugin install ewe.ssh
    ewe-plugin remove ewe.ssh          # gone until you add it back

Needs `ssh` (openssh) and `kitty` — both ewe dependencies. Hosts are added
to `~/.ssh/config` by hand or from Settings → Network → SSH (`ewe-conf`'s
`[network.ssh]` managed block); this plugin only reads them.

## Files

Browse scripts live in `~/.config/quickshell/ssh-browse/<host>.sh` — the
same place the shell kept them before this feature became a plugin, so
nothing you saved is lost. They are not synced and not part of `ewe.conf`.

## Settings, IPC

No settings. No IPC target of its own; the page opens with
`qs ipc call quicksettings tab ssh` or `Shell.openQuickSettings("ssh")`.

Three entry points (`Tile.qml`, `Page.qml`, `Status.qml`) over one state
singleton (`Ssh.qml`, declared in `qmldir`).
