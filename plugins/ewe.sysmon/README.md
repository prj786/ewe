# System monitor — an ewe plugin

`ewe.sysmon` — first-party, shipped inside the ewe payload.

CPU and memory meters on the Quick settings home grid (one full-width
tile), and a compact readout in the top bar if you want one. The numbers
are sampled only while something shows them — the tile while Quick
settings is open, the bar readout while it is on — every 1.5 s, or every
3 s on battery.

Install: Komble → Plugins, or

    ewe-plugin install ewe.sysmon

The bar readout is the host's Show in bar switch (Komble → Plugins → System
monitor → Options, or `ewe-plugin bar ewe.sysmon on`): a bar module with the
CPU and memory percentages, right section; off by default
(`barWidget.defaultShown: false`) because a bar widget polls for the whole
session. Click it to open Quick settings. 1.0's own `show_in_bar` setting is
gone (1.1.0); a value it stored still counts until Show in bar is set.

No IPC. Needs only `sh`: `sample.sh` reads `/proc/stat` and `/proc/meminfo`
in one process per tick and prints one JSON object — `./test.sh` checks it.
