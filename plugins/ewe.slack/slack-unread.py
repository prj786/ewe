#!/usr/bin/env python3
"""slack-unread.py — one pass over your Slack DMs, one JSON line out.

Run by SlackInbox.qml every poll. Reads the user token (xoxp-…) from the
keyring itself (`secret-tool lookup service ewe-slack account user-token`), so
the token never reaches QML, argv or a file. Prints exactly one line:

  {"ok": true, "team": "T…", "self": "U…", "total": 3,
   "list": [{"channel", "kind", "user", "name", "avatar", "text", "ts", "count"}]}
  {"ok": false, "error": "no-token" | "auth" | "offline" | "<slack error>"}

Slack has no public "unread count" for a user token, so a DM is unread when
its newest message from someone else is newer than its `last_read`. Slack allows
about 50 conversations.info calls a minute, so one run checks at most
MAX_CHECKS DMs: unread, new and recently active ones first, then the ones
checked longest ago, so every DM is looked at within SWEEP_S or so.
Avatars are cached under the state dir; names and activity in cache.json.
"""

import argparse
import concurrent.futures
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://slack.com/api/"
RECENT_DAYS = 14
SWEEP_S = 15 * 60
MAX_CHECKS = 40
USER_TTL_S = 24 * 3600
WORKERS = 3
PREVIEW_MAX = 160


class SlackError(Exception):
    pass


def token():
    try:
        out = subprocess.run(
            ["secret-tool", "lookup", "service", "ewe-slack", "account", "user-token"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return out.stdout.strip()


def call(tok, method, **params):
    url = API + method + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + tok})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                j = json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                time.sleep(min(int(e.headers.get("Retry-After", "5")), 30))
                continue
            raise SlackError("http-%d" % e.code)
        if j.get("ok"):
            return j
        if j.get("error") == "ratelimited" and attempt < 4:
            time.sleep(5)
            continue
        raise SlackError(j.get("error", "unknown"))
    raise SlackError("ratelimited")


def paged(tok, method, key, **params):
    out, cursor = [], ""
    while True:
        extra = {"cursor": cursor} if cursor else {}
        j = call(tok, method, limit=200, **extra, **params)
        out.extend(j.get(key, []))
        cursor = (j.get("response_metadata") or {}).get("next_cursor", "")
        if not cursor:
            return out


def load_cache(path):
    try:
        with open(path) as f:
            c = json.load(f)
        if isinstance(c, dict):
            c.setdefault("users", {})
            c.setdefault("chans", {})
            return c
    except (OSError, ValueError):
        pass
    return {"users": {}, "chans": {}}


def save_cache(path, cache):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f)
    os.replace(tmp, path)


def user_info(tok, cache, avatars_dir, uid):
    now = time.time()
    u = cache["users"].get(uid)
    if u and now - u.get("at", 0) < USER_TTL_S and (not u.get("avatar") or os.path.exists(u["avatar"])):
        return u
    try:
        p = call(tok, "users.info", user=uid)["user"]
    except SlackError:
        return u or {"name": uid, "avatar": "", "bot": False, "at": 0}
    prof = p.get("profile") or {}
    name = prof.get("display_name") or prof.get("real_name") or p.get("real_name") or p.get("name") or uid
    url = prof.get("image_72") or prof.get("image_48") or ""
    avatar = ""
    if url:
        ext = os.path.splitext(urllib.parse.urlparse(url).path)[1] or ".png"
        avatar = os.path.join(avatars_dir, uid + ext)
        if not u or u.get("avatarUrl") != url or not os.path.exists(avatar):
            try:
                with urllib.request.urlopen(url, timeout=15) as r, open(avatar + ".tmp", "wb") as f:
                    f.write(r.read())
                os.replace(avatar + ".tmp", avatar)
            except (OSError, urllib.error.URLError):
                avatar = ""
    u = {"name": name, "avatar": avatar, "avatarUrl": url,
         "bot": bool(p.get("is_bot")) or uid == "USLACKBOT", "at": now}
    cache["users"][uid] = u
    return u


def clean_text(text, users):
    def mention(m):
        uid = m.group(1)
        return "@" + (users.get(uid, {}).get("name") or uid)
    text = re.sub(r"<@([UW][A-Z0-9]+)(?:\|[^>]*)?>", mention, text)
    text = re.sub(r"<#[CG][A-Z0-9]+\|([^>]*)>", r"#\1", text)
    text = re.sub(r"<!(here|channel|everyone)[^>]*>", r"@\1", text)
    text = re.sub(r"<([^|>]+)\|([^>]+)>", r"\2", text)
    text = re.sub(r"<([^>]+)>", r"\1", text)
    text = html.unescape(" ".join(text.split()))
    return text[:PREVIEW_MAX - 1] + "…" if len(text) > PREVIEW_MAX else text


def preview(msg, users):
    t = clean_text(msg.get("text") or "", users)
    if t:
        return t
    if msg.get("files"):
        return "Sent a file"
    if msg.get("attachments") or msg.get("blocks"):
        return "Sent a message"
    return ""


def is_from_other(msg, me):
    if msg.get("user") == me:
        return False
    return msg.get("subtype") in (None, "file_share", "thread_broadcast", "bot_message", "me_message")


def check(tok, chan, me):
    """(None | (newest unread msg, count from others), newest ts seen)."""
    info = call(tok, "conversations.info", channel=chan["id"])["channel"]
    last_read = info.get("last_read") or "0"
    latest = info.get("latest")
    if isinstance(latest, dict) and latest.get("ts"):
        if float(latest["ts"]) <= float(last_read) or not is_from_other(latest, me):
            return None, latest["ts"]
    # a DM never opened reads "0000000000.000000", which Slack refuses as `oldest`
    since = {"oldest": last_read} if float(last_read) > 0 else {}
    hist = call(tok, "conversations.history", channel=chan["id"], limit=20, **since)
    msgs = [m for m in hist.get("messages", []) if float(m.get("ts", "0")) > float(last_read)]
    newest_ts = msgs[0]["ts"] if msgs else (latest or {}).get("ts")
    theirs = [m for m in msgs if is_from_other(m, me)]
    if not theirs:
        return None, newest_ts
    return (theirs[0], len(theirs)), newest_ts


def run(state_dir, include_bots):
    tok = token()
    if not tok:
        return {"ok": False, "error": "no-token"}
    avatars_dir = os.path.join(state_dir, "avatars")
    os.makedirs(avatars_dir, exist_ok=True)
    cache_path = os.path.join(state_dir, "cache.json")
    cache = load_cache(cache_path)
    try:
        auth = call(tok, "auth.test")
    except SlackError as e:
        err = str(e)
        return {"ok": False, "error": "auth" if err in ("invalid_auth", "not_authed", "token_revoked", "account_inactive") else err}
    me, team = auth["user_id"], auth["team_id"]

    chans = paged(tok, "conversations.list", "channels", types="im,mpim", exclude_archived="true")
    now = time.time()
    recent_cut = now - RECENT_DAYS * 86400
    urgent, stale = [], []
    for c in chans:
        if c.get("is_im") and c.get("is_user_deleted"):
            continue
        known = cache["chans"].get(c["id"])
        if not known or known.get("unread") or float(known.get("latest") or 0) > recent_cut:
            urgent.append(c)
        elif now - known.get("checked", 0) > SWEEP_S:
            stale.append(c)
    stale.sort(key=lambda c: cache["chans"][c["id"]].get("checked", 0))
    todo = (urgent + stale)[:MAX_CHECKS]

    results = {}
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        futs = {pool.submit(check, tok, c, me): c for c in todo}
        for f in concurrent.futures.as_completed(futs):
            try:
                results[futs[f]["id"]] = f.result()
            except SlackError:
                continue

    out = []
    for c in chans:
        if c["id"] not in results:
            continue
        hit, newest_ts = results[c["id"]]
        cache["chans"][c["id"]] = {"latest": newest_ts or "0", "unread": hit is not None, "checked": now}
        if hit is None:
            continue
        msg, count = hit
        sender = msg.get("user") or ""
        if c.get("is_im"):
            u = user_info(tok, cache, avatars_dir, c["user"])
            if u.get("bot") and not include_bots:
                continue
            name, avatar, uid = u["name"], u["avatar"], c["user"]
        else:
            try:
                members = [m for m in paged(tok, "conversations.members", "members", channel=c["id"]) if m != me]
            except SlackError:
                members = []
            names = [user_info(tok, cache, avatars_dir, m)["name"] for m in members[:4]]
            name = ", ".join(names) or c.get("name", "Group")
            s = user_info(tok, cache, avatars_dir, sender) if sender else {"avatar": ""}
            avatar, uid = s["avatar"], sender
        for m in sorted(set(re.findall(r"<@([UW][A-Z0-9]+)", msg.get("text") or "")))[:5]:
            user_info(tok, cache, avatars_dir, m)
        out.append({
            "channel": c["id"], "kind": "im" if c.get("is_im") else "mpim",
            "user": uid, "name": name, "avatar": avatar,
            "text": preview(msg, cache["users"]),
            "ts": msg["ts"], "count": count,
        })

    save_cache(cache_path, cache)
    out.sort(key=lambda r: float(r["ts"]), reverse=True)
    return {"ok": True, "team": team, "self": me, "total": sum(r["count"] for r in out), "list": out}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--include-bots", action="store_true")
    a = ap.parse_args()
    try:
        res = run(a.state_dir, a.include_bots)
    except (urllib.error.URLError, OSError):
        res = {"ok": False, "error": "offline"}
    except SlackError as e:
        res = {"ok": False, "error": str(e)}
    print(json.dumps(res), flush=True)


if __name__ == "__main__":
    sys.exit(main())
