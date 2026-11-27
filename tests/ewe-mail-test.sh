#!/usr/bin/env bash
# ewe-mail test — many accounts against tests/mock-imap.py + tests/mock-smtp.py
# (plain TCP on loopback, allowed only by EWE_MAIL_INSECURE=1) and
# tests/mock-autoconfig.py (the ISPDB stand-in: no network). Sandboxed XDG_*,
# fake keyring, a scratch ewe.conf. Covers:
#   * nothing configured: status / accounts / unseen / logout
#   * login tests IMAP AND SMTP: a wrong IMAP or SMTP password, an SMTP
#     server that is not there → nothing recorded; a good one → keyring (IMAP
#     and a separate SMTP password) + [[accounts.mail]], no secret in the file,
#     and the SMTP server never saw MAIL/RCPT/DATA
#   * a second account; accounts, status (first account, + count), unseen
#     default / --account / --all (merged newest first)
#   * set <id> name; logout <id>; logout with no id (which / the only one)
#   * the old single [accounts.mail] table reads as one account and becomes a
#     list at the next write
#   * autoconfig: the built-in table, the ISPDB, the provider's own host, the
#     guess, a bad address
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$WORK"' EXIT

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
CONF="$XDG_CONFIG_HOME/ewe/ewe.conf"

wait_port() { for _ in $(seq 1 30); do (echo > /dev/tcp/127.0.0.1/$1) 2>/dev/null && return; sleep 0.2; done; }
base=$(( (RANDOM % 20000) + 30000 ))
PORT=$base; SPORT=$((base + 1)); HPORT=$((base + 2)); DEAD=$((base + 3))
python3 "$HERE/tests/mock-imap.py" "$PORT" >"$WORK/imap.log" 2>&1 &
python3 "$HERE/tests/mock-smtp.py" "$SPORT" --log "$WORK/smtp.log" tester:mail-pass smtp-user:smtp-pass ann@example.org:ann-pass >"$WORK/smtp.out" 2>&1 &
python3 "$HERE/tests/mock-autoconfig.py" "$HPORT" "$PORT" "$SPORT" >"$WORK/http.log" 2>&1 &
wait_port "$PORT"; wait_port "$SPORT"; wait_port "$HPORT"
export EWE_MAIL_ISPDB="http://127.0.0.1:$HPORT/v1.1/"
export EWE_MAIL_AUTOCONFIG_URL="http://127.0.0.1:$HPORT/domain/{domain}/config"

# 1 · nothing configured
r=$("$EM" status)
[ "$(jget "$r" "['configured']")" = "False" ] && [ "$(jget "$r" "['count']")" = "0" ] || fail "status empty: $r"
[ "$(jget "$("$EM" accounts)" "['accounts']")" = "[]" ] || fail "accounts empty"
r=$("$EM" unseen)
[ "$(jget "$r" "['error']")" = "not-configured" ] || fail "unseen unconfigured: $r"
r=$("$EM" unseen --all)
[ "$(jget "$r" "['error']")" = "not-configured" ] || fail "unseen --all unconfigured: $r"
[ "$(jget "$("$EM" logout)" "['ok']")" = "True" ] || fail "logout with nothing"
ok "unconfigured: status, accounts, unseen, logout say so"

# 2 · login tests IMAP and SMTP before it stores anything
none() { [ "$(jget "$("$EM" accounts)" "['accounts'].__len__()")" = "0" ] && [ ! -s "$WORK/keyring" ] || fail "$1: must record nothing"; }
r=$(echo "wrong" | "$EM" login 127.0.0.1 tester --port "$PORT" --smtp-host 127.0.0.1 --smtp-port "$SPORT")
[ "$(jget "$r" "['error']")" = "auth-failed" ] || fail "wrong IMAP password: $r"
none "wrong IMAP password"
r=$(printf 'mail-pass\nnot-the-smtp-pass\n' | "$EM" login 127.0.0.1 tester --port "$PORT" --smtp-host 127.0.0.1 --smtp-port "$SPORT" --smtp-user smtp-user)
[ "$(jget "$r" "['error']")" = "smtp-auth-failed" ] || fail "wrong SMTP password: $r"
none "wrong SMTP password"
r=$(echo "mail-pass" | "$EM" login 127.0.0.1 tester --port "$PORT" --smtp-host 127.0.0.1 --smtp-port "$DEAD")
[ "$(jget "$r" "['error']")" = "smtp-network" ] || fail "no SMTP server: $r"
none "unreachable SMTP"
r=$(echo "mail-pass" | "$EM" login 127.0.0.1 tester --port "$DEAD" --smtp-host 127.0.0.1 --smtp-port "$SPORT")
[ "$(jget "$r" "['error']")" = "network" ] || fail "no IMAP server: $r"
none "unreachable IMAP"
ok "login: wrong IMAP / wrong SMTP / no SMTP / no IMAP all refuse and record nothing"

# 3 · a good login: separate SMTP password on line 2, name, email
r=$(printf 'mail-pass\nsmtp-pass\n' | "$EM" login 127.0.0.1 tester --port "$PORT" --email Tess@Example.org --name "Tess T" \
      --smtp-host 127.0.0.1 --smtp-port "$SPORT" --smtp-security starttls --smtp-user smtp-user)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "login: $r"
[ "$(jget "$r" "['account']['id']")" = "imap:tess@example.org" ] || fail "id lowercase: $r"
[ "$(jget "$r" "['account']['smtp_security']")" = "starttls" ] || fail "smtp_security: $r"
[ "$(jget "$r" "['host']")" = "127.0.0.1" ] && [ "$(jget "$r" "['user']")" = "tester" ] || fail "compat fields: $r"
grep -q 'mail-pass' "$WORK/keyring" || fail "IMAP password not in the (fake) keyring"
grep -q 'smtp-pass' "$WORK/keyring" || fail "SMTP password not in the (fake) keyring"
! grep -q -e 'mail-pass' -e 'smtp-pass' "$CONF" || fail "a password leaked into ewe.conf"
grep -q 'accounts.mail' "$CONF" || fail "[[accounts.mail]] not recorded"
grep -q 'smtp_user = "smtp-user"' "$CONF" || fail "smtp_user not recorded"
! grep -qE '^(MAIL|RCPT|DATA)' "$WORK/smtp.log" || fail "the SMTP test sent mail"
grep -q '^AUTH' "$WORK/smtp.log" || fail "the SMTP test did not authenticate"
ok "login: IMAP + SMTP tested; both passwords in the keyring, none in the file; no mail sent"

# 4 · a second account — servers by autoconfig (no --smtp-host)
r=$(echo "ann-pass" | "$EM" login 127.0.0.1 ann@example.org --port "$PORT" --email ann@ispdb.test --name "Ann")
[ "$(jget "$r" "['ok']")" = "True" ] || fail "second login: $r"
[ "$(jget "$r" "['account']['smtp_port']")" = "$SPORT" ] || fail "autoconfig did not give the SMTP port: $r"
[ "$(jget "$r" "['account']['id']")" = "imap:ann@ispdb.test" ] || fail "second id: $r"
r=$("$EM" accounts)
[ "$(jget "$r" "['accounts'].__len__()")" = "2" ] || fail "two accounts: $r"
[ "$(jget "$r" "['accounts'][0]['name']")" = "Tess T" ] && [ "$(jget "$r" "['accounts'][1]['keyring']")" = "True" ] || fail "accounts shape: $r"
[ "$(jget "$r" "['accounts'][0]['smtp_user']")" = "smtp-user" ] && [ "$(jget "$r" "['accounts'][1]['smtp_user']")" = "ann@example.org" ] || fail "smtp_user: $r"
# the same address again replaces, never duplicates, and keeps the name
r=$(echo "ann-pass" | "$EM" login 127.0.0.1 ann@example.org --port "$PORT" --email ann@ispdb.test)
[ "$(jget "$("$EM" accounts)" "['accounts'].__len__()")" = "2" ] || fail "re-login must replace"
[ "$(jget "$("$EM" accounts)" "['accounts'][1]['name']")" = "Ann" ] || fail "re-login keeps the name"
# the old single-account answer: the FIRST account, same fields, + count
r=$("$EM" status)
[ "$(jget "$r" "['configured']")" = "True" ] && [ "$(jget "$r" "['host']")" = "127.0.0.1" ] && [ "$(jget "$r" "['user']")" = "tester" ] \
  && [ "$(jget "$r" "['port']")" = "$PORT" ] && [ "$(jget "$r" "['starttls']")" = "False" ] && [ "$(jget "$r" "['keyring']")" = "True" ] \
  && [ "$(jget "$r" "['count']")" = "2" ] || fail "status: $r"
ok "two accounts: autoconfig fills SMTP, re-login replaces, status = first account + count"

# 5 · unseen: default (first, unchanged), --account, --all
r=$("$EM" unseen --limit 5)
[ "$(jget "$r" "['ok']")" = "True" ] && [ "$(jget "$r" "['unread']")" = "2" ] && [ "$(jget "$r" "['list'].__len__()")" = "2" ] || fail "unseen: $r"
[ "$(jget "$r" "['list'][0]['id']")" = "103" ] || fail "newest first (uid 103): $r"
[ "$(jget "$r" "['list'][0]['subject']")" = "Server — all good" ] || fail "RFC 2047 subject"
[ "$(jget "$r" "['list'][1]['from']")" = "Nino Berað" ] || fail "encoded display name"
[ "$(jget "$r" "['host']")" = "127.0.0.1" ] && [ "$(jget "$r" "['user']")" = "tester" ] || fail "host/user fields kept"
r=$("$EM" unseen --account imap:ann@ispdb.test)
[ "$(jget "$r" "['unread']")" = "1" ] && [ "$(jget "$r" "['list'][0]['id']")" = "201" ] || fail "--account: $r"
r=$("$EM" unseen --all --limit 10)
[ "$(jget "$r" "['unread']")" = "3" ] && [ "$(jget "$r" "['list'].__len__()")" = "3" ] || fail "--all sums: $r"
[ "$(jget "$r" "['list'][0]['account']")" = "imap:ann@ispdb.test" ] && [ "$(jget "$r" "['list'][0]['subject']")" = "Second inbox" ] || fail "--all newest first: $r"
[ "$(jget "$r" "['accounts'].__len__()")" = "2" ] && [ "$(jget "$r" "['accounts'][1]['unread']")" = "1" ] || fail "--all accounts: $r"
[ "$(jget "$("$EM" unseen --account imap:nobody@x.org)" "['error']")" = "not-found" ] || fail "unknown --account"
ok "unseen: default = first account, --account, --all merged newest first with account + per-account counts"

# 6 · set name, logout
r=$("$EM" set imap:ann@ispdb.test name "Ann Aardvark")
[ "$(jget "$r" "['ok']")" = "True" ] && [ "$(jget "$("$EM" accounts)" "['accounts'][1]['name']")" = "Ann Aardvark" ] || fail "set name: $r"
[ "$(jget "$("$EM" set imap:ghost@x.org name X)" "['error']")" = "not-found" ] || fail "set unknown"
r=$("$EM" logout)
[ "$(jget "$r" "['error']")" = "which" ] || fail "logout with several and no id: $r"
[ "$(jget "$("$EM" accounts)" "['accounts'].__len__()")" = "2" ] || fail "which must remove nothing"
r=$("$EM" logout imap:ann@ispdb.test)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "logout id: $r"
! grep -q 'ann-pass' "$WORK/keyring" || fail "the removed account's password survived"
grep -q 'mail-pass' "$WORK/keyring" || fail "logout <id> removed the other account's password"
[ "$(jget "$("$EM" accounts)" "['accounts'].__len__()")" = "1" ] || fail "one left"
ok "set name; logout with several asks which; logout <id> removes record + keyring entry only for that one"

# 7 · logout with no id removes the only account (what the installed ewe Sync does)
r=$("$EM" logout)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "logout: $r"
! grep -q -e 'mail-pass' -e 'smtp-pass' "$WORK/keyring" || fail "keyring entries survived logout"
[ "$(jget "$("$EM" unseen)" "['error']")" = "not-configured" ] || fail "after logout"
ok "logout with no id removes the only account, its IMAP and SMTP passwords"

# 8 · the old single table reads as one account; the next write makes a list
"$HERE/bin/ewe-conf" set --no-hooks accounts.mail "{\"host\":\"127.0.0.1\",\"user\":\"tester\",\"port\":$PORT,\"starttls\":false}"
printf '{"127.0.0.1\\ntester": "mail-pass"}' > "$WORK/keyring"
grep -q '^\[accounts.mail\]\|mail = {' "$CONF" || fail "legacy table not written as such: $(cat "$CONF")"
r=$("$EM" accounts)
[ "$(jget "$r" "['accounts'].__len__()")" = "1" ] && [ "$(jget "$r" "['accounts'][0]['keyring']")" = "True" ] || fail "legacy accounts: $r"
[ "$(jget "$r" "['accounts'][0]['id']")" = "imap:tester@127.0.0.1" ] || fail "legacy id: $r"
[ "$(jget "$("$EM" status)" "['host']")" = "127.0.0.1" ] && [ "$(jget "$("$EM" unseen)" "['unread']")" = "2" ] || fail "legacy status/unseen"
echo "ann-pass" | "$EM" login 127.0.0.1 ann@example.org --port "$PORT" --email ann@ispdb.test >/dev/null
r=$("$EM" accounts)
[ "$(jget "$r" "['accounts'].__len__()")" = "2" ] && [ "$(jget "$r" "['accounts'][0]['user']")" = "tester" ] || fail "legacy + new: $r"
grep -q '^\[\[accounts.mail\]\]' "$CONF" || grep -q 'mail = \[' "$CONF" || fail "not a list after the write: $(cat "$CONF")"
ok "the old [accounts.mail] table reads as one account and becomes a list at the next write"

# 9 · autoconfig
ac() { "$EM" autoconfig "$1"; }
r=$(ac you@gmail.com)
[ "$(jget "$r" "['source']")" = "builtin" ] && [ "$(jget "$r" "['imap']['host']")" = "imap.gmail.com" ] && [ "$(jget "$r" "['smtp']['port']")" = "465" ] || fail "gmail: $r"
[ -n "$(jget "$r" "['note']")" ] || fail "gmail note"
r=$(ac you@iCloud.com)
[ "$(jget "$r" "['user']")" = "local" ] && [ "$(jget "$r" "['smtp']['security']")" = "starttls" ] || fail "icloud: $r"
r=$(ac you@outlook.com);  [ "$(jget "$r" "['smtp']['host']")" = "smtp.office365.com" ] || fail "outlook: $r"
r=$(ac you@fastmail.com); [ "$(jget "$r" "['note']")" = "" ] && [ "$(jget "$r" "['source']")" = "builtin" ] || fail "fastmail: $r"
r=$(ac you@proton.me);    [ "$(jget "$r" "['imap']['host']")" = "" ] && [ -n "$(jget "$r" "['note']")" ] || fail "proton: $r"
r=$(ac you@ispdb.test)
[ "$(jget "$r" "['source']")" = "ispdb" ] && [ "$(jget "$r" "['imap']['port']")" = "$PORT" ] && [ "$(jget "$r" "['smtp']['security']")" = "starttls" ] || fail "ispdb: $r"
r=$(ac jo@own.test)
[ "$(jget "$r" "['source']")" = "domain" ] && [ "$(jget "$r" "['imap']['host']")" = "imap.own.test" ] && [ "$(jget "$r" "['user']")" = "local" ] || fail "domain host: $r"
r=$(ac you@nothing-here.test)
[ "$(jget "$r" "['source']")" = "guess" ] && [ "$(jget "$r" "['imap']['host']")" = "imap.nothing-here.test" ] && [ "$(jget "$r" "['smtp']['host']")" = "smtp.nothing-here.test" ] && [ "$(jget "$r" "['user']")" = "email" ] || fail "guess: $r"
[ "$(jget "$(ac not-an-address)" "['error']")" = "bad-email" ] || fail "bad address"
ok "autoconfig: built-in table, ISPDB, the provider's host, the guess, a bad address (no network)"

echo "ALL PASS"
