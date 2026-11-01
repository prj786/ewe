#!/usr/bin/env python3
"""net-state.py — the network as it really is, in one JSON object.

NetState.qml runs this on every (debounced) NetworkManager event and hands the
answer to the bar and Quick settings, so both say the same thing. Before it,
the shell knew only "ethernet connected: yes/no" and "Wi-Fi connected:
yes/no" — a cable with link but no DHCP lease (the owner's work desktop,
2026-10-28: NM retried every 45 s, then blocked the port for 5 minutes) looked
exactly like no cable at all, and a link with no internet looked online.

  connectivity  NetworkManager's verdict: full · limited · portal · none ·
                unknown (unknown = not checked; never shown as a problem)
  primary       {dev, type} — the device a packet to the internet leaves by
                (`ip route get`, so policy routing — a Tailscale exit node, a
                wg-quick tunnel — counts), or null
  uplink        {dev, type} — the PHYSICAL link carrying it (ethernet / wifi),
                the lowest-metric default route of the main table; the bar
                shows this one's glyph (NM gives a cable metric 100 and Wi-Fi
                600, so a cable that is up wins — it used to be Wi-Fi always)
  devices       [{dev, type, state, detail, connection, internet}]
  wired         [{dev, state, detail, connection, internet, carrier, speed,
                  maxSpeed, partnerMax, autoconnect, reason, driver}]
                speed in Mb/s from /sys/class/net/<dev>/speed; maxSpeed is
                the fastest mode the NIC supports and partnerMax the fastest
                the other end advertises (`ethtool <dev>`, unprivileged) —
                null when unknown
  wifi          {dev, state, detail, connection, internet} | null
  vpns          [{name, type, dev, state, tailscale, carriesTraffic}]

state is the device state's first word (connected · connecting ·
disconnected · unavailable · unmanaged · failed · deactivating); detail is
the bracketed rest ("getting IP configuration"). internet is the device's
own connectivity, the better of IPv4 and IPv6.

Read-only: only nmcli queries, `ip route`, sysfs and `ethtool <dev>`. Prints
{"ok": false, "error": …} if NetworkManager does not answer; always exits 0.
"""
import json
import os
import re
import shutil
import subprocess
import sys

SYSFS = os.environ.get("EWE_NET_SYSFS") or "/sys/class/net"     # tests point it at a fixture
RANK = {"full": 4, "portal": 3, "limited": 2, "none": 1, "unknown": 0}
PHYSICAL = ("ethernet", "wifi")
VPN_TYPES = ("vpn", "wireguard", "tun")


def run(cmd, timeout=4):
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (subprocess.TimeoutExpired, OSError):
        return None, ""


def terse(line):
    """Split one `nmcli -t` line on unescaped ':' and undo the \\: \\\\ escapes."""
    out, cur, i = [], [], 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ":":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def split_state(raw):
    raw = (raw or "").strip()
    m = re.match(r"^([a-z-]+)\s*(?:\((.*)\))?", raw)
    if not m:
        return raw, ""
    return m.group(1), (m.group(2) or "")


def best(*words):
    w = [x for x in words if x in RANK]
    return max(w, key=lambda x: RANK[x]) if w else "unknown"


def sysfs(dev, name):
    try:
        with open(os.path.join(SYSFS, dev, name)) as f:
            return f.read().strip()
    except OSError:          # EINVAL while the interface is down
        return None


def ethtool_modes(dev):
    """(maxSpeed, partnerMax) in Mb/s from `ethtool <dev>`, None when unknown."""
    if not shutil.which("ethtool"):
        return None, None
    rc, o = run(["ethtool", dev], 3)
    if not o:
        return None, None
    blocks, key = {}, None
    for ln in o.splitlines():
        s = ln.strip()
        if not s:
            continue
        if ":" in s:
            key, val = s.split(":", 1)
            key = key.strip()
            blocks[key] = [val.strip()]
        elif key is not None:
            blocks[key].append(s)

    def fastest(k):
        speeds = [int(x) for x in re.findall(r"(\d+)base", " ".join(blocks.get(k, [])))]
        return max(speeds) if speeds else None
    return fastest("Supported link modes"), fastest("Link partner advertised link modes")


def default_routes():
    """[(dev, metric)] of the main table's default routes, v4 then v6."""
    out = []
    for fam in ("-4", "-6"):
        rc, o = run(["ip", "-j", fam, "route", "show", "default"])
        try:
            for r in json.loads(o or "[]"):
                if r.get("dev"):
                    out.append((r["dev"], int(r.get("metric") or 0)))
        except (ValueError, TypeError):
            pass
    return out


def route_get():
    for fam, dst in (("-4", "1.1.1.1"), ("-6", "2606:4700:4700::1111")):
        rc, o = run(["ip", "-j", fam, "route", "get", dst])
        if rc != 0:
            continue
        try:
            r = json.loads(o or "[]")
            if r and r[0].get("dev"):
                return r[0]["dev"]
        except (ValueError, TypeError, IndexError, AttributeError):
            pass
    return ""


def main():
    rc, o = run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,IP4-CONNECTIVITY,IP6-CONNECTIVITY,CONNECTION",
                 "device", "status"])
    if rc != 0:
        print(json.dumps({"ok": False, "error": "NetworkManager is not answering"}))
        return
    devices = []
    for ln in o.splitlines():
        if not ln.strip():
            continue
        f = terse(ln)
        if len(f) < 6:
            continue
        state, detail = split_state(f[2])
        devices.append({"dev": f[0], "type": f[1], "state": state, "detail": detail,
                        "connection": f[5], "internet": best(f[3], f[4])})
    types = {d["dev"]: d["type"] for d in devices}

    rc, o = run(["nmcli", "-t", "networking", "connectivity"])
    connectivity = (o.strip() if rc == 0 else "") or "unknown"

    pdev = route_get()
    primary = {"dev": pdev, "type": types.get(pdev, "")} if pdev else None
    uplink = None
    phys = sorted((m, dev) for dev, m in default_routes() if types.get(dev) in PHYSICAL)
    if phys:
        uplink = {"dev": phys[0][1], "type": types[phys[0][1]]}
    elif primary and primary["type"] in PHYSICAL:
        uplink = dict(primary)

    wired = []
    for d in devices:
        if d["type"] != "ethernet":
            continue
        w = dict(d)
        rc, o = run(["nmcli", "-t", "-f",
                     "GENERAL.AUTOCONNECT,GENERAL.REASON,GENERAL.DRIVER,WIRED-PROPERTIES.CARRIER",
                     "device", "show", d["dev"]])
        props = {}
        for ln in o.splitlines():
            if ":" in ln:
                k, v = ln.split(":", 1)
                props[k] = v.replace("\\:", ":").strip()
        c = sysfs(d["dev"], "carrier")
        if c in ("0", "1"):
            carrier = c == "1"
        else:
            carrier = props.get("WIRED-PROPERTIES.CARRIER") == "on"
        speed = None
        if carrier:
            try:
                s = int(sysfs(d["dev"], "speed") or "-1")
                speed = s if s > 0 else None
            except ValueError:
                pass
        mx, partner = ethtool_modes(d["dev"]) if carrier else (None, None)
        w.update({"carrier": carrier, "speed": speed, "maxSpeed": mx, "partnerMax": partner,
                  "autoconnect": props.get("GENERAL.AUTOCONNECT", "yes") != "no",
                  "reason": props.get("GENERAL.REASON", ""), "driver": props.get("GENERAL.DRIVER", "")})
        wired.append(w)

    wifi = next((dict(d) for d in devices if d["type"] == "wifi"), None)

    vpns = []
    rc, o = run(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"])
    for ln in o.splitlines():
        f = terse(ln)
        if len(f) < 4 or f[1] not in VPN_TYPES:
            continue
        ts = f[2].startswith("tailscale") or f[0].startswith("tailscale")
        vpns.append({"name": f[0], "type": f[1], "dev": f[2], "state": f[3], "tailscale": ts,
                     "carriesTraffic": bool(pdev) and (f[2] == pdev or (f[1] == "vpn" and types.get(pdev, "") not in PHYSICAL
                                                                         and not pdev.startswith("tailscale")))})

    print(json.dumps({"ok": True, "connectivity": connectivity, "primary": primary, "uplink": uplink,
                      "devices": devices, "wired": wired, "wifi": wifi, "vpns": vpns}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:      # never a traceback where the shell expects JSON
        print(json.dumps({"ok": False, "error": "net-state: %s" % e}))
    sys.exit(0)
