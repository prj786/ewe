#!/usr/bin/env bash
# ewe-mail test — the IMAP badge reader against tests/mock-imap.py (plain
# TCP on loopback, allowed only by EWE_MAIL_INSECURE=1). Sandboxed XDG_*,
# fake keyring, a scratch ewe.conf. Covers:
#   * status when nothing is configured
#   * login: wrong password → auth-failed and nothing recorded; right
#     password → keyring entry + [accounts.mail] in ewe.conf (no secret)
#   * unseen: count, the two unseen rows newest first, decoded headers, UIDs
#   * logout clears the keyring and the account; unseen → not-configured
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK 2>/dev/null || true; rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export XDG_CACHE_HOME="$WORK/cache"
export XDG_RUNTIME_DIR="$WORK/run"
export XDG_STATE_HOME="$WORK/state"
mkdir -p "$XDG_CONFIG_HOME/ewe" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
export EWE_MAIL_FAKE_KEYRING="$WORK/keyring"
export EWE_MAIL_INSECURE=1
export HYPRLAND_INSTANCE_SIGNATURE=

fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }
EM="$HERE/bin/ewe-mail"

PORT=$(( (RANDOM % 20000) + 30000 ))
python3 "$HERE/tests/mock-imap.py" "$PORT" >"$WORK/mock.log" 2>&1 &
MOCK=$!
for _ in $(seq 1 30); do (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.2; done

# 1 · nothing configured
r=$("$EM" status)
[ "$(jget "$r" "['configured']")" = "False" ] || fail "status empty: $r"
r=$("$EM" unseen)
[ "$(jget "$r" "['error']")" = "not-configured" ] || fail "unseen unconfigured: $r"
ok "unconfigured: status + unseen say so"

# 2 · login
r=$(echo "wrong" | "$EM" login 127.0.0.1 tester --port "$PORT")
[ "$(jget "$r" "['error']")" = "auth-failed" ] || fail "wrong password: $r"
[ "$("$EM" status | python3 -c 'import json,sys;print(json.load(sys.stdin)["configured"])')" = "False" ] || fail "wrong password must record nothing"
r=$(echo "mail-pass" | "$EM" login 127.0.0.1 tester --port "$PORT")
[ "$(jget "$r" "['ok']")" = "True" ] || fail "login: $r"
grep -q 'mail-pass' "$WORK/keyring" || fail "password not in the (fake) keyring"
! grep -q 'mail-pass' "$XDG_CONFIG_HOME/ewe/ewe.conf" || fail "password leaked into ewe.conf"
grep -qE 'mail = \{.*host = "127.0.0.1"' "$XDG_CONFIG_HOME/ewe/ewe.conf" || fail "[accounts.mail] not recorded"
r=$("$EM" status)
[ "$(jget "$r" "['configured']")" = "True" ] && [ "$(jget "$r" "['keyring']")" = "True" ] || fail "status after login: $r"
ok "login: rejected password records nothing; accepted one → keyring + [accounts.mail], no secret in the file"

# 3 · unseen
r=$("$EM" unseen --limit 5)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "unseen: $r"
[ "$(jget "$r" "['unread']")" = "2" ] || fail "unread count: $r"
[ "$(jget "$r" "['list'].__len__()")" = "2" ] || fail "two rows"
[ "$(jget "$r" "['list'][0]['id']")" = "103" ] || fail "newest first (uid 103): $r"
[ "$(jget "$r" "['list'][0]['subject']")" = "Server — all good" ] || fail "RFC 2047 subject decoded: $(jget "$r" "['list'][0]['subject']")"
[ "$(jget "$r" "['list'][1]['from']")" = "Nino Berað" ] || fail "encoded display name: $(jget "$r" "['list'][1]['from']")"
[ "$(jget "$r" "['list'][1]['date']")" -gt 0 ] || fail "date parsed"
ok "unseen: count, newest first, decoded From/Subject, UIDs"

# 4 · logout
r=$("$EM" logout)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "logout: $r"
! grep -q 'mail-pass' "$WORK/keyring" || fail "keyring entry survived logout"
r=$("$EM" unseen)
[ "$(jget "$r" "['error']")" = "not-configured" ] || fail "after logout: $r"
ok "logout clears the keyring and the account"

echo "ALL PASS"
