#!/usr/bin/env bash
# wifi-profiles.sh — every saved Wi-Fi profile as "<ssid>\t<profile name>\t<psk>"
# (psk = "stored" when the key is in the profile, "agent" when NetworkManager
# expects a secret agent to supply it, "none" for an open network).
#
# The shell used to decide "saved → no password prompt" by matching the SSID
# against profile NAMES from `nmcli connection show`. That is wrong twice:
# a profile need not be named after its SSID, and a name with spaces or
# colons (this box has one called "786  ", trailing spaces included) is easy
# to mangle. `nmcli` cannot list 802-11-wireless.ssid across profiles in one
# call, so ask per profile — a handful of tiny reads. Output is tab-separated
# with nmcli's "\:" escapes undone; the QML splits on \t only.
set -u
nmcli -t -f NAME,TYPE connection show 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        *:802-11-wireless) ;;
        *) continue ;;
    esac
    name="${line%:802-11-wireless}"
    name="${name//\\:/:}"
    ssid="$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null)"
    [ -n "$ssid" ] || continue
    kmgmt="$(nmcli -g 802-11-wireless-security.key-mgmt connection show "$name" 2>/dev/null)"
    flags="$(nmcli -g 802-11-wireless-security.psk-flags connection show "$name" 2>/dev/null)"
    if [ -z "$kmgmt" ]; then psk=none
    elif [ "${flags%% *}" = "0" ] || [ -z "$flags" ]; then psk=stored
    else psk=agent
    fi
    printf '%s\t%s\t%s\n' "$ssid" "$name" "$psk"
done
