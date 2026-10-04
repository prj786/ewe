# VPN — an ewe add-on

`ewe.vpn` — first-party, shipped inside the ewe payload, installed on request.

Your NetworkManager VPN connections (OpenVPN, L2TP/IPsec, WireGuard, …) in
Quick settings. A split tile on the home grid: the body disconnects the
active VPN, or connects the only one you have (with several, it opens the
list); the chevron opens the VPN page, where every profile is a row — click
to connect or disconnect. A shield sits in the bar's Quick settings pill
while a VPN is up, a spinner while one is connecting.

**Signing in.** ewe has no NetworkManager secret agent, so a profile
without stored secrets cannot connect on its own. The row then opens a
sign-in form right under it — username, password, and for L2TP/IPsec the
pre-shared key. Connect stores them in the profile (`password-flags=0`, the
"store for all users" setting; the file is root-only under
`/etc/NetworkManager`) and the toggle works from then on.

**When it fails.** The notification carries the real reason: when
NetworkManager only says "The VPN service failed to start", the add-on
reads the plugin's line from the NetworkManager journal (readable for the
installing user) and shows that instead — for an IPsec failure with the
hint that L2TP/IPsec needs IKEv1 (libreswan, set up by ewe's installer).

## Install

Komble → Add-ons, or:

    ewe-plugin install ewe.vpn
    ewe-plugin remove ewe.vpn          # gone until you add it back

Needs `nmcli` (networkmanager, an ewe dependency). The VPN types come from
their NetworkManager plugins — `networkmanager-openvpn`,
`networkmanager-l2tp` (+ `libreswan` for IPsec) — which ewe installs;
profiles are created in Settings → Network → VPN (`ewe-conf`'s
`[network.vpn]`), by import, or with `nmcli`. This add-on lists and toggles
them; it never creates one.

## How it stays fresh

One `nmcli monitor` process (dies with the shell) re-reads the state when
NetworkManager changes anything, so a VPN brought up from Settings or a
script shows at once; plus one read at start, after wake, and whenever the
tile or the page appears.

## Settings, IPC

No settings. No IPC target of its own; the page opens with
`qs ipc call quicksettings tab vpn` or `Shell.openQuickSettings("vpn")`.

Three entry points (`Tile.qml`, `Page.qml`, `Status.qml`) over one state
singleton (`Vpn.qml`, declared in `qmldir`).
