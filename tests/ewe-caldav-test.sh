#!/usr/bin/env bash
# ewe-caldav test — the calendar reader against tests/mock-nextcloud.py.
# No network, no real server, no keyring, no real config (XDG_* sandboxed,
# the fake keyring, the mock's loopback exception). Covers:
#   * the ICS parser alone: TZID, UTC, all-day, DURATION, VALARM, RECURRENCE-ID
#   * signed out → not-signed-in, no crash
#   * events against the mock: three events, right shapes, sorted, cached
#   * the cache: a second call is served from it; --no-cache refetches;
#     an unreachable server returns the cache with offline=true
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK 2>/dev/null || true; rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export XDG_CACHE_HOME="$WORK/cache"
export XDG_RUNTIME_DIR="$WORK/run"
export XDG_STATE_HOME="$WORK/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
export EWE_CLOUD_FAKE_KEYRING="$WORK/keyring"
export EWE_CLOUD_NO_BROWSER=1
export EWE_CLOUD_SERVER_INSECURE=1

fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }
EC="$HERE/bin/ewe-cloud"; CAL="$HERE/bin/ewe-caldav"

# 1 · the parser alone
cat > "$WORK/sample.ics" <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a@x
SUMMARY:Timed\, with a comma
LOCATION:Somewhere
DTSTART;TZID=Europe/Tbilisi:20260903T100000
DTEND;TZID=Europe/Tbilisi:20260903T110000
BEGIN:VALARM
TRIGGER:-PT15M
ACTION:DISPLAY
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:b@x
SUMMARY:All day
DTSTART;VALUE=DATE:20260904
DTEND;VALUE=DATE:20260905
END:VEVENT
BEGIN:VEVENT
UID:c@x
RECURRENCE-ID:20260905T080000Z
SUMMARY:Instance
DTSTART:20260905T080000Z
DURATION:PT45M
END:VEVENT
BEGIN:VEVENT
UID:d@x
STATUS:CANCELLED
SUMMARY:Gone
DTSTART:20260906T080000Z
END:VEVENT
END:VCALENDAR
ICS
r=$("$CAL" parse "$WORK/sample.ics")
[ "$(jget "$r" "['ok']")" = "True" ] || fail "parse: $r"
[ "$(jget "$r" "['events'].__len__()")" = "3" ] || fail "parse count (cancelled must drop): $r"
[ "$(jget "$r" "['events'][0]['summary']")" = "Timed, with a comma" ] || fail "unescape"
[ "$(jget "$r" "['events'][0]['start']")" = "2026-09-03T10:00:00+04:00" ] || fail "TZID start: $(jget "$r" "['events'][0]['start']")"
[ "$(jget "$r" "['events'][0]['reminders']")" = "[15]" ] || fail "VALARM"
[ "$(jget "$r" "['events'][0]['location']")" = "Somewhere" ] || fail "location"
[ "$(jget "$r" "['events'][1]['allDay']")" = "True" ] && [ "$(jget "$r" "['events'][1]['start']")" = "2026-09-04" ] || fail "all-day"
[ "$(jget "$r" "['events'][1]['reminders']")" = "[]" ] || fail "all-day has no default reminder"
[ "$(jget "$r" "['events'][2]['id']")" = "c@x@20260905T080000Z" ] || fail "recurrence id"
[ "$(jget "$r" "['events'][2]['end']")" = "2026-09-05T08:45:00+00:00" ] || fail "DURATION end: $(jget "$r" "['events'][2]['end']")"
[ "$(jget "$r" "['events'][2]['reminders']")" = "[10]" ] || fail "timed default reminder"
ok "ICS parser: TZID, all-day, DURATION, VALARM, RECURRENCE-ID, CANCELLED"

# 2 · signed out
r=$("$CAL" events)
[ "$(jget "$r" "['error']")" = "not-signed-in" ] || fail "signed out: $r"
ok "signed out → not-signed-in"

# 3 · sign in to the mock, then real events
PORT=$(( (RANDOM % 20000) + 30000 ))
python3 "$HERE/tests/mock-nextcloud.py" "$PORT" "$WORK/nc.json" >"$WORK/mock.log" 2>&1 &
MOCK=$!
SRV="http://127.0.0.1:$PORT"
for _ in $(seq 1 30); do curl -s -o /dev/null "$SRV/index.php/login/v2" && break; sleep 0.2; done
( sleep 0.6; url=$(cat "$XDG_RUNTIME_DIR/ewe-cloud-login-url"); curl -s -o /dev/null "$url" ) &
r=$("$EC" login "$SRV")
[ "$(jget "$r" "['ok']")" = "True" ] || fail "login: $r"

r=$("$CAL" calendars)
[ "$(jget "$r" "['calendars'][0]['name']")" = "Personal" ] || fail "calendars: $r"
[ "$(jget "$r" "['calendars'][0]['color']")" = "#0082C9" ] || fail "calendar colour trimmed to #rrggbb"
ok "calendars listed from the calendar home"

r=$("$CAL" events --days 7)
[ "$(jget "$r" "['ok']")" = "True" ] && [ "$(jget "$r" "['offline']")" = "False" ] || fail "events: $r"
[ "$(jget "$r" "['events'].__len__()")" = "3" ] || fail "three events: $r"
[ "$(jget "$r" "['events'][0]['summary']")" = "Standup" ] || fail "sorted by start: $r"
[ "$(jget "$r" "['events'][0]['calendar']")" = "Personal" ] && [ "$(jget "$r" "['events'][0]['color']")" = "#0082C9" ] || fail "calendar name/colour on the event"
[ "$(jget "$r" "['events'][1]['allDay']")" = "True" ] || fail "all-day second"
[ "$(jget "$r" "['events'][2]['id']" | grep -c '@')" = "1" ] || fail "instance id"
[ -s "$XDG_CACHE_HOME/ewe/caldav-events.json" ] || fail "cache written"
ok "events from the mock: three, sorted, shaped like the shell expects"

# 4 · cache: served from it, bypassed with --no-cache, kept when offline
r=$("$CAL" events)
[ "$(jget "$r" "['cached']")" = "True" ] || fail "second call not cached: $r"
r=$("$CAL" events --no-cache)
[ "$(jget "$r" "['cached']")" = "False" ] || fail "--no-cache refetched: $r"
kill $MOCK; wait $MOCK 2>/dev/null || true
r=$("$CAL" events --no-cache)
[ "$(jget "$r" "['ok']")" = "True" ] && [ "$(jget "$r" "['offline']")" = "True" ] || fail "offline flag: $r"
[ "$(jget "$r" "['events'].__len__()")" = "3" ] || fail "offline keeps the cache"
ok "cache: hit, --no-cache, offline fallback"

echo "ALL PASS"
