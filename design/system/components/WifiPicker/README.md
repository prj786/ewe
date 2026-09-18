# Wi-Fi picker

The Wi-Fi picker lists nearby networks and joins one, with the password typed right in the list.

## Where it's used
- The network step of Welcome and the Wi-Fi details in Quick settings.

## Anatomy
1. Status line: 16px icon and 13px weight 600 text: "Connected to <network>" in `success` with `circle-check`, or "Not connected. Pick a network." / "Wi-Fi is off" in `text-secondary` with `wifi-off`.
2. "Turn on Wi-Fi" link, only while Wi-Fi is off.
3. List box: `surface-sunken`, 1px `border-subtle`, `primary` radius, 4px padding, scrolls after 8 rows.
4. Network row: 28px, `secondary` radius, signal glyph (`wifi`, `wifi-high`, `wifi-low`, `wifi-zero`), name, a `lock` for secured networks, and `check` (connected) or a Spinner (joining).
5. Password row: replaces the row being joined: a borderless field, a show/hide `eye` button and a small primary "Join", inside a `focus-ring` outline.
6. Error line: `danger`, 12px, with `circle-alert`.

## States
- Row hover `surface-hover`; focus `focus-width` `focus-ring` inside the edge; connected row in `accent-text` weight 600.
- Scanning: "Looking for networks…" with a Spinner. None found: "No networks found."
- A rejected password reopens the password row with the error below.

## Behavior
- The list refreshes every few seconds while visible. Enter joins; Esc closes the password row.

## Accessibility
- A list box; rows say name, signal strength, security and state (“office, weak signal, secured”).

## Where it lives
`dotfiles/quickshell/WifiPicker.qml`.

## What a build provides
`enabled` · `networks` (ssid, signal, secured, active) · `state` · `error` · `onJoin` · `onEnable`.
