#!/bin/sh
# cast-check.sh — preflight for "Cast to TV" (the Quick Settings tile /
# Super+Shift+C → Cast.qml → gnome-network-displays). Checks what a smart-TV
# mirror needs and says, as a notification AND on stdout, exactly what is
# missing and the command that fixes it:
#
#   gnome-network-displays   the app (AUR)                         — FATAL, exit 2
#   Wi-Fi Direct (P2P)       Miracast: Samsung "Screen Mirroring", Android TV.
#                            Hardware + driver; `iw list` knows. Also refuses an
#                            iwd-backed NetworkManager (no P2P there)
#   avahi-daemon             Chromecast / Google TV discovery (mDNS)
#   portal capture           xdg-desktop-portal-hyprland < 1.4.1-1.1 freezes the
#                            capture for good the first time the encoder returns
#                            a buffer late (upstream #424) → "static image"
#   quality (one toast)      software-only H.264, Wi-Fi on 2.4 GHz, regulatory
#                            domain unset → Miracast lag / frozen frames
#
# Exit 0 = all good, 1 = something degraded (the app still launches — a
# Chromecast-only setup is fine), 2 = nothing can work.
# Cast.qml runs this once per session; run it by hand any time.
set -u

APP="Cast to TV"
ICON="video-display"
status=0
quality=""

say()  { printf '%s\n' "$2"; notify-send -a "$APP" -i "$ICON" -u "$1" -h "string:x-canonical-private-synchronous:ewe-cast-$3" "$APP" "$2" 2>/dev/null || true; }
hint() { printf '%s\n' "$1"; quality="${quality}${quality:+
}• $1"; status=1; }

# ── 1. the app ──
if ! command -v gnome-network-displays >/dev/null 2>&1; then
    say critical "Install gnome-network-displays:  paru -S gnome-network-displays" app
    exit 2
fi

# ── 2. Miracast: Wi-Fi Direct via NetworkManager + wpa_supplicant ──
if ! systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
    say normal "NetworkManager isn't running — Miracast (Wi-Fi Direct) is unavailable; Chromecast still works." nm
    status=1
elif grep -rhsiE '^[[:space:]]*wifi\.backend[[:space:]]*=[[:space:]]*iwd' \
        /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d 2>/dev/null | grep -q .; then
    say normal "NetworkManager uses the iwd backend, which has no Wi-Fi Direct — Miracast won't work (Chromecast will). Switch wifi.backend to wpa_supplicant to mirror to Samsung / Android TVs." iwd
    status=1
fi
if ! command -v iw >/dev/null 2>&1; then
    say low "Can't verify Wi-Fi Direct support (iw missing):  sudo pacman -S iw" iw
    status=1
elif ! iw list 2>/dev/null | grep -qE 'P2P-client|P2P-GO'; then
    say normal "This Wi-Fi card reports no Wi-Fi Direct (P2P) — Miracast (Samsung Screen Mirroring, Android TV) won't work. Chromecast / Google TV still does." p2p
    status=1
fi

# ── 3. Chromecast: mDNS discovery ──
if ! systemctl is-active --quiet avahi-daemon.service 2>/dev/null; then
    say normal "avahi-daemon isn't running — Chromecast / Google TV won't be found:  sudo systemctl enable --now avahi-daemon" avahi
    status=1
fi

# ── 4. the screen capture itself: xdph's screencopy freeze (fixed after 1.4.1;
#       ewe ships the fixes as 1.4.1-1.1 from packages/patched) ──
xdph=$(pacman -Q xdg-desktop-portal-hyprland 2>/dev/null | awk '{print $2}')
if [ -n "$xdph" ] && command -v vercmp >/dev/null 2>&1 && [ "$(vercmp "$xdph" 1.4.1-1.1)" -lt 0 ]; then
    say critical "Screen capture will FREEZE mid-stream (xdg-desktop-portal-hyprland $xdph, bug fixed after 1.4.1). Re-run install.sh — it builds the patched 1.4.1-1.1 — then restart the portal." xdph
    status=1
fi

# ── 5. quality — one toast, only when there is something to say ──
if ! gst-inspect-1.0 vah264enc >/dev/null 2>&1; then
    hint "Software H.264 only — install gst-plugin-va for hardware encoding (less lag, less CPU)."
fi
if iw reg get 2>/dev/null | grep -q 'country 00'; then
    hint "Wi-Fi regulatory domain is unset, so 5 GHz Wi-Fi Direct is disabled — install wireless-regdb and set WIRELESS_REGDOM in /etc/conf.d/wireless-regdom (install.sh does this)."
fi
wifi=$(iw dev 2>/dev/null | awk '/Interface/{i=$2} /type managed/{print i; exit}')
if [ -n "$wifi" ]; then
    freq=$(iw dev "$wifi" link 2>/dev/null | awk '/freq:/{print int($2); exit}')
    if [ -n "$freq" ] && [ "$freq" -lt 3000 ] 2>/dev/null; then
        hint "Wi-Fi is on 2.4 GHz ($wifi, ${freq} MHz): Miracast shares that channel with your internet link — expect lag. Use a 5 GHz network, or disconnect Wi-Fi while casting."
    fi
fi
[ -n "$quality" ] && say low "Miracast quality:
$quality" quality

[ "$status" = 0 ] && printf 'cast: ready (gnome-network-displays, Wi-Fi Direct, avahi, patched portal, hardware encode)\n'
exit "$status"
