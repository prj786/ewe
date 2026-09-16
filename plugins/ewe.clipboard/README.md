# Clipboard & emoji — an ewe plugin

`ewe.clipboard` — first-party, shipped with ewe, removable.

A scissors icon in the top bar. Click it: your clipboard history (via
[cliphist](https://github.com/sentriz/cliphist)) and an emoji grid, click to
copy. A service records every text and image copy — except passwords: a copy
marked by a password manager, a copy made while a password manager window is
focused, or one made by ewe's own fill picker never enters the history.

    ewe-plugin remove ewe.clipboard        # gone until you add it back
    ewe-plugin add https://github.com/prj786/ewe-plugin-clipboard.git --enable

Settings (Komble → Plugins, or `ewe-plugin set ewe.clipboard emoji false`):
`emoji` — show the emoji tab.

Needs `cliphist` and `wl-clipboard` (both ewe dependencies).

Three entry points, one IPC target: `qs ipc call ewe.clipboard toggle`.
