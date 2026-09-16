# Screenshot — an ewe plugin

`ewe.screenshot` — first-party, shipped with ewe, removable.

A camera in the top bar — left click a region, right click the whole screen,
middle click the focused window — and the keys: `Print` (screen),
`Shift+Print` (region), `Super+Print` (window). Shots land in
`~/Pictures/Screenshots` and pile into a preview stack bottom-right: drag it
into any app to drop the files, click to copy the newest.

    ewe-plugin remove ewe.screenshot
    ewe-plugin add https://github.com/prj786/ewe-plugin-screenshot.git --enable

Setting: `copy` — also copy each shot to the clipboard (default on).
Needs `grim`, `slurp`, `wl-clipboard` (ewe dependencies). IPC target
`ewe.screenshot`: `shoot full|region|activewindow`, `pop <path>`, `dismiss`.
