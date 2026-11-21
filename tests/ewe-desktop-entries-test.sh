#!/usr/bin/env bash
# desktop-entries.py: CRLF .desktop files get LF copies under the cache (the
# user's file untouched), only the file that wins its id is copied, stale
# copies go, and translated entries report their untranslated Name.
# Hermetic: a throwaway HOME / XDG_* tree.
set -u
cd "$(dirname "$0")/.."
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }
P=dotfiles/quickshell/scripts/desktop-entries.py
U="$S/home/.local/share/applications"
SYS="$S/sys/applications"
mkdir -p "$U" "$SYS/sub"
printf '[Desktop Entry]\r\nName=Word\r\nExec=true word %%F\r\nType=Application\r\nMimeType=application/msword;' > "$U/word.desktop"
printf '[Desktop Entry]\r\nName=Excel\r\nExec=true\r\nType=Application\r\n' > "$U/excel.desktop"
printf '[Desktop Entry]\nName=Files\nName[ka]=ფაილები\nType=Application\nExec=true\n' > "$SYS/files.desktop"
printf '[Desktop Entry]\nName=Plain\nType=Application\nExec=true\n' > "$SYS/plain.desktop"
printf '[Desktop Entry]\r\nName=Sub\r\nType=Application\r\nExec=true\r\n' > "$SYS/sub/thing.desktop"
# a CRLF file shadowed by a good user file of the same id: nothing to copy
printf '[Desktop Entry]\r\nName=Shadowed\r\nType=Application\r\n' > "$SYS/good.desktop"
printf '[Desktop Entry]\nName=Good\nType=Application\nExec=true\n' > "$U/good.desktop"
before="$(sha256sum "$U/word.desktop")"
run() { env HOME="$S/home" XDG_DATA_HOME= XDG_CACHE_HOME="$S/cache" XDG_DATA_DIRS="$S/sys" python3 "$P" "$@"; }
out="$(run)"
F="$S/cache/ewe/desktop-entries/applications"
echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"]' && ok "prints ok JSON" || no "bad JSON: $out"
[ -f "$F/word.desktop" ] && ! grep -q $'\r' "$F/word.desktop" && ok "word.desktop copied without CR" || no "no LF copy of word.desktop"
[ "$(tail -c1 "$F/word.desktop" | od -An -c | tr -d ' ')" = '\n' ] && ok "the copy ends with a newline" || no "no final newline"
[ "$(sha256sum "$U/word.desktop")" = "$before" ] && ok "the user's file is untouched" || no "the user's file changed"
[ -f "$F/sub/thing.desktop" ] && ok "a subfolder entry keeps its path (same id)" || no "sub/thing.desktop not copied"
[ ! -e "$F/good.desktop" ] && ok "a shadowed CRLF file is not copied" || no "copied a shadowed file"
[ ! -e "$F/plain.desktop" ] && ok "LF files are left alone" || no "copied an LF file"
echo "$out" | grep -q '"files": "Files"' && ok "english name of a translated entry" || no "no english name: $out"
echo "$out" | grep -q '"plain"' && no "an untranslated entry listed in english" || ok "untranslated entries are not listed"
echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert sorted(d["fixed"])==["excel","sub-thing","word"], d["fixed"]' \
  && ok "fixed ids: excel, sub-thing, word" || no "fixed ids wrong: $out"
m1="$(stat -c %Y.%i "$F/word.desktop")"; sleep 1.1; run >/dev/null
[ "$(stat -c %Y.%i "$F/word.desktop")" = "$m1" ] && ok "an unchanged copy is not rewritten" || no "the copy was rewritten (rescan loop)"
rm "$U/excel.desktop"; tr -d '\r' < "$SYS/sub/thing.desktop" > "$SYS/sub/t" && mv "$SYS/sub/t" "$SYS/sub/thing.desktop"
run >/dev/null
[ ! -e "$F/excel.desktop" ] && ok "a copy whose source is gone is removed" || no "stale excel copy kept"
[ ! -e "$F/sub" ] && ok "a copy whose source was fixed is removed (and its empty folder)" || no "stale sub/ copy kept"
[ "$(run --dir)" = "$S/cache/ewe/desktop-entries" ] && ok "--dir prints the copies' base" || no "--dir wrong"
exit $fail
