#!/usr/bin/env bash
# ewe-conf and quoted keys: a plugin id has dots, so its settings live under
# plugins.settings."ewe.passwords". A plain split of the dotted key once wrote
# a stray [plugins.settings."\"ewe"] table and left the real setting alone
# (2026-10-15). A quoted part keeps its dots; a broken key is refused.
# Hermetic: a throwaway XDG_CONFIG_HOME, stub qs and hyprctl on PATH.
set -u
cd "$(dirname "$0")/.."
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/bin"
printf '#!/bin/sh\necho "qs $*" >> "%s/calls.log"\n' "$S" > "$S/bin/qs"
printf '#!/bin/sh\necho "hyprctl $*" >> "%s/calls.log"\n' "$S" > "$S/bin/hyprctl"
chmod +x "$S/bin/qs" "$S/bin/hyprctl"
export PATH="$S/bin:$PATH" XDG_CONFIG_HOME="$S/cfg" XDG_STATE_HOME="$S/state"
export HYPRLAND_INSTANCE_SIGNATURE=test-only-stub
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }
CONF="$S/cfg/ewe/ewe.conf"

bin/ewe-conf set 'plugins.settings."ewe.passwords"' '{"provider": "1password", "press_enter": true}' \
  || no "setting a whole table under a quoted id failed"
bin/ewe-conf set 'plugins.settings."ewe.passwords".provider' ewe || no "set through a quoted id exited non-zero"
[ "$(bin/ewe-conf get 'plugins.settings."ewe.passwords".provider')" = "ewe" ] \
  && ok "a quoted id reaches the real setting" || no "get through a quoted id"
[ "$(bin/ewe-conf get "plugins.settings.'ewe.passwords'.press_enter")" = "true" ] \
  && ok "single quotes work, the sibling key survived" || no "press_enter lost or single quotes refused"
grep -q '"ewe.passwords" = {' "$CONF" && ok "the table keeps its quoted id" || no "no \"ewe.passwords\" table in the file"
grep -q '\\"ewe' "$CONF" && no "a stray \"\\\"ewe\" table was written" || ok "no stray table"

before="$(cat "$CONF")"
for bad in 'plugins.settings."ewe.passwords.provider' 'plugins..settings' 'plugins.settings."ewe"x' '.plugins' 'plugins.'; do
  bin/ewe-conf set "$bad" 1 2>"$S/err" && no "a broken key was accepted: $bad" || {
    grep -q '"bad-key"' "$S/err" && ok "refused with bad-key: $bad" || no "no bad-key error for: $bad"
  }
done
[ "$(cat "$CONF")" = "$before" ] && ok "refused keys changed nothing" || no "a refused key changed the file"

bin/ewe-conf unset 'plugins.settings."ewe.passwords".press_enter' || no "unset through a quoted id exited non-zero"
bin/ewe-conf get 'plugins.settings."ewe.passwords".press_enter' >/dev/null 2>&1 \
  && no "unset left the key" || ok "unset through a quoted id"
[ "$(bin/ewe-conf get desktop.theme.accent)" != "" ] && ok "plain keys still work" || no "a plain key broke"

# [desktop.language] (2026-11-21): spelling dictionaries + the on/off switch
[ "$(bin/ewe-conf get desktop.language.check_spelling)" = "true" ] \
  && ok "check_spelling defaults to true" || no "check_spelling has no default"
bin/ewe-conf get desktop.language.spellcheck >/dev/null 2>&1 \
  && no "spellcheck has a value before it was set" || ok "spellcheck unset = automatic"
: > "$S/calls.log"
bin/ewe-conf set desktop.language.spellcheck '["en_US", "ka_GE", "en_US", "ro_RO-ante1993", "es"]' \
  || no "setting the dictionaries failed"
[ "$(bin/ewe-conf get desktop.language.spellcheck)" = '["en_US", "ka_GE", "ro_RO-ante1993", "es"]' ] \
  && ok "dictionaries kept in order, duplicates dropped" || no "spellcheck: $(bin/ewe-conf get desktop.language.spellcheck)"
grep -q 'hyprctl' "$S/calls.log" && no "a language key reloaded Hyprland (full apply)" || ok "a language key applies nothing else"
for bad in '["en_US; rm -rf /"]' '["../x"]' '["EN"]' '"en_US"x'; do
  bin/ewe-conf set desktop.language.spellcheck "$bad" 2>/dev/null && no "accepted a bad dictionary list: $bad" || ok "refused: $bad"
done
bin/ewe-conf set desktop.language.check_spelling off || no "check_spelling off failed"
[ "$(bin/ewe-conf get desktop.language.check_spelling)" = "false" ] && ok "check_spelling off" || no "check_spelling not off"
bin/ewe-conf set desktop.language.check_spelling maybe 2>/dev/null && no "check_spelling took 'maybe'" || ok "check_spelling refuses non-bools"

# any Unicode character can be written (2026-11-27). The emitter used JSON's
# escapes, and JSON writes a character beyond U+FFFF as a surrogate pair,
# which TOML refuses: an emoji in ANY value failed the write (a folder named
# "📚 Books", an AppImage called "Rocket 🚀"), and one already in the file —
# valid TOML when typed by hand — failed every write after it.
same() { python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1]) == json.loads(sys.argv[2]) else 1)' "$1" "$2"; }
parses() { python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$CONF" 2>/dev/null; }
V='["/home/u/📚 Books", "/home/u/ქართული/ფაილი", "del\u007fete", "say \"hi\" \\ back", "tab\there"]'
bin/ewe-conf set apps.places "$V" 2>"$S/err" && ok "a value with an emoji, Georgian, DEL, quotes and a tab is written" \
  || no "the emitter refused a character: $(tail -1 "$S/err")"
same "$(bin/ewe-conf get apps.places)" "$V" && ok "…and reads back the same" || no "round trip: $(bin/ewe-conf get apps.places)"
parses && ok "…and the file is TOML" || no "the file no longer parses"
grep -q 'U0001F4DA' "$CONF" && grep -q 'u007f' "$CONF" && ok "beyond U+FFFF is \\UXXXXXXXX, DEL is \\u007f" || no "escapes: $(grep -m1 places "$CONF")"
grep -q 'u10e5' "$CONF" && ok "the rest is written as before (existing files do not change)" || no "a BMP character changed its spelling"
bin/ewe-conf set 'plugins.settings."acme.🙂"' '{"mood": "🙂"}' && [ "$(bin/ewe-conf get 'plugins.settings."acme.🙂".mood')" = "🙂" ] && parses \
  && ok "a quoted key takes it too" || no "an emoji in a key"
printf '\n[handmade]\nnote = "🐑 typed by hand"\n' >> "$CONF"
bin/ewe-conf set desktop.layout.gaps_in 7 2>"$S/err" && [ "$(bin/ewe-conf get desktop.layout.gaps_in)" = "7" ] \
  && [ "$(bin/ewe-conf get handmade.note)" = "🐑 typed by hand" ] && parses \
  && ok "an emoji typed into the file by hand no longer fails every later write" || no "a write after a hand-typed emoji: $(tail -1 "$S/err")"

# …and what cannot be written is refused with an answer, not a traceback:
# TOML has no null, half a surrogate pair is not a character
before="$(cat "$CONF")"
for bad in 'null' '{"a": null}' '[1, null]' '[{"name": "x", "exec": null}]' '"\ud83d"'; do
  bin/ewe-conf set apps.startup "$bad" 2>"$S/err" && no "accepted an unwritable value: $bad" || {
    grep -q '"bad-value"' "$S/err" && ! grep -q Traceback "$S/err" && ok "refused with bad-value: $bad" || no "no clean refusal for $bad: $(tail -1 "$S/err")"
  }
done
bin/ewe-conf absorb user-theme '{"accent": null}' 2>"$S/err" && no "absorb took a null" || {
  grep -q '"bad-value"' "$S/err" && ! grep -q Traceback "$S/err" && ok "absorb refuses a null the same way" || no "absorb: $(tail -1 "$S/err")"
}
[ "$(cat "$CONF")" = "$before" ] && ok "refused values changed nothing" || no "a refused value changed the file"

# rule 2 — no credential rides in a URL the file keeps (it goes to the
# account). plugins.sources is the address `ewe-plugin add` was given, a
# scheme's `source` the one `ewe-theme scheme import` fetched: both used to
# be written as typed, token and all.
bin/ewe-conf set plugins.sources '{"acme.a": "https://user:s3cret@example.org/a.git", "acme.b": "https://ghp_tokenAsUser@github.com/x/b.git", "acme.c": "ssh://git:pw0rd@example.org/c.git", "acme.d": "ssh://git@example.org:2222/d.git", "acme.e": "git@github.com:x/e.git", "acme.f": "https://example.org:8443/p@th/f.git", "ewe.dock": "bundled", "acme.g": "local"}' \
  || no "setting plugins.sources failed"
same "$(bin/ewe-conf get plugins.sources)" '{"acme.a": "https://example.org/a.git", "acme.b": "https://github.com/x/b.git", "acme.c": "ssh://git@example.org/c.git", "acme.d": "ssh://git@example.org:2222/d.git", "acme.e": "git@github.com:x/e.git", "acme.f": "https://example.org:8443/p@th/f.git", "ewe.dock": "bundled", "acme.g": "local"}' \
  && ok "plugins.sources: http(s) loses its user part, ssh keeps the user and loses the password, the rest is untouched" \
  || no "plugins.sources: $(bin/ewe-conf get plugins.sources)"
bin/ewe-conf set --no-hooks desktop.theme.schemes '[{"name": "X", "slug": "x", "source": "https://me:t0ken@example.org/x.yaml"}, {"name": "Y", "slug": "y", "source": "/home/u/y.yaml"}]' \
  || no "setting desktop.theme.schemes failed"
same "$(bin/ewe-conf get desktop.theme.schemes)" '[{"name": "X", "slug": "x", "source": "https://example.org/x.yaml"}, {"name": "Y", "slug": "y", "source": "/home/u/y.yaml"}]' \
  && ok "a scheme's source URL the same; a path stays" || no "schemes: $(bin/ewe-conf get desktop.theme.schemes)"
grep -q -E 's3cret|ghp_tokenAsUser|pw0rd|t0ken' "$CONF" && no "a credential is in the file" || ok "no credential in the file"
sed -i 's|"https://example.org/a.git"|"https://old:le4k@example.org/a.git"|' "$CONF"     # as it arrives from an older machine
grep -q 'le4k' "$CONF" || no "(test) the old-style line was not planted"
bin/ewe-conf set desktop.layout.gaps_in 8 && ! grep -q 'le4k' "$CONF" \
  && ok "one that arrived in the file is gone with the next write" || no "an old credential survived a write"
exit $fail
