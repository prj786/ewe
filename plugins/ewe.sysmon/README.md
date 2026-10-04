# System monitor — an ewe plugin

`ewe.sysmon` — first-party, shipped inside ewe as an add-on.

CPU and memory meters on the Quick settings home grid (one full-width
tile), and a compact readout in the top bar if you want one. The numbers
are sampled only while something shows them — the tile while Quick
settings is open, the bar readout while it is on — every 1.5 s, or every
3 s on battery.

Install: Komble → Add-ons, or

    ewe-plugin install ewe.sysmon

Settings (Komble → Add-ons, or `ewe-plugin set ewe.sysmon show_in_bar true`):
`show_in_bar` — a bar module with the CPU and memory percentages, right
section; off by default because a bar widget polls for the whole session.
Click it to open Quick settings.

No IPC. Needs only `sh`: `sample.sh` reads `/proc/stat` and `/proc/meminfo`
in one process per tick and prints one JSON object — `./test.sh` checks it.
