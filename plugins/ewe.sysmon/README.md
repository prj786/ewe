# System monitor — an ewe plugin

`ewe.sysmon` — first-party, shipped inside the ewe payload.

CPU, memory and internet speed in the bar. Click the readout for the
details, and put the same card on your desktop if you want it.

Install: Komble → Plugins, or

    ewe-plugin install ewe.sysmon

## What you get

- **In the bar** — a small readout, on by default: `7%  39%  ↓ 1.2 MB/s`.
  *In the bar* chooses what it shows: all three, CPU + memory, or only the
  speed (then download and upload). *Show in the bar* is ewe's own switch
  (Komble → Plugins → System monitor, or `ewe-plugin bar ewe.sysmon off`).
- **The card** — click the readout: CPU with the last minute as a line,
  memory ("6.1 GB of 15.5 GB", how much is in swap), and the internet:
  download, upload and the connection they go through ("Wi-Fi · home",
  "Ethernet", "VPN", "Offline"). The cog opens the plugin in Komble.
- **On the desktop** — the same numbers as a desktop widget. Off until you
  turn it on: the card's *Show on desktop* switch, or *Show on the desktop*
  in Komble. Both are ewe's own switch (`ewe-plugin place ewe.sysmon
  --visible on|off`), so they always agree. Drag it, pin it above your
  windows or lock it like any widget.

Speeds are in MB/s like downloads (1024-based, as browsers count) or, with
*Speed in* set to Mbit/s, in bits like speed tests (1000-based).

    ewe-plugin set ewe.sysmon bar_shows "CPU + memory"    # "All three" | "CPU + memory" | "Speed"
    ewe-plugin set ewe.sysmon speed_unit Mbit/s           # "MB/s" | "Mbit/s"

Since 2.0.0 the plugin is no longer in Quick settings (the CPU and memory
tile is gone); the readout opens its own card instead.

## How it measures

Nothing is sampled unless something shows it: the readout while its bar is
up, the card while it is open, the widget while it is on the desktop. Then
every 1.5 s, or every 3 s on battery, one `sh` process (`sample.sh`) reads
`/proc/stat`, `/proc/meminfo`, the default route (`/proc/net/route`, lowest
metric), that interface's byte counters (`/proc/net/dev`) and the clock
(`/proc/uptime`), and prints one JSON object. The speed is the change in
the counters over the real time between two samples; there is none on the
first sample, after the connection changed interface, or after a counter
reset. Wi-Fi is told from `/sys/class/net/<if>/wireless`; the network name
comes from the shell's own network reading.

`./test.sh` checks `sample.sh` against fixture files (`SYSMON_STAT`,
`SYSMON_MEMINFO`, `SYSMON_ROUTE`, `SYSMON_NETDEV`, `SYSMON_UPTIME`,
`SYSMON_SYSNET`) and once against the real machine.

IPC: `qs ipc call ewe.sysmon toggle|hide` opens or closes the card (under
the readout on the focused screen). Needs only `sh`.
