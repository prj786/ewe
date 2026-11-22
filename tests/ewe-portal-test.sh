#!/usr/bin/env bash
# ewe-portal tests (RFC-011) — two halves:
#   1. the pure helpers, loaded straight from bin/ewe-portal with python3 -I in
#      a sandboxed HOME: MIME → globs, filters and choices, `ay` paths, URIs,
#      the sidebar's places, recent files, remembered folders, the answer →
#      results rules and portals.conf routing;
#   2. the whole chain on a PRIVATE session bus (dbus-run-session): the real
#      xdg-desktop-portal frontend → ewe-portal serve → a fake `qs` that plays
#      the shell (answers, cancels, is missing, loses the picker). The GTK
#      fallback runs with XDG_RUNTIME_DIR and the display variables
#      sandboxed, so it can never reach the live session — it fails, which
#      is the point: the app gets response 2 instead of a hang.
# Never touches the host's bus, portal or ~/.config.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

# ── 1. helpers ──────────────────────────────────────────────────────────────
H="$SB/home"
mkdir -p "$H/.config/gtk-3.0" "$H/.config/ewe" "$H/.config/xdg-desktop-portal" \
         "$H/.local/share" "$H/.local/state/ewe" "$H/Docs" "$H/Work Stuff" "$H/Pics" \
         "$H/Projects" "$H/Nextcloud" "$SB/mime" "$SB/media/USBKEY"
cat > "$SB/mime/globs2" <<'G'
# test db
50:application/pdf:*.pdf
50:text/plain:*.txt
50:text/x-python:*.py
50:image/png:*.png
50:image/jpeg:*.jpg
50:image/jpeg:*.jpeg
G
printf 'text/x-python text/plain\n' > "$SB/mime/subclasses"
printf 'image/jpg image/jpeg\n' > "$SB/mime/aliases"
cat > "$H/.config/user-dirs.dirs" <<'U'
XDG_DESKTOP_DIR="$HOME"
XDG_DOCUMENTS_DIR="$HOME/Docs"
XDG_PICTURES_DIR="$HOME/Pics"
U
printf 'file://%s/Work%%20Stuff Work\nfile://%s/Docs\nsftp://example.org/x Remote\n' "$H" "$H" > "$H/.config/gtk-3.0/bookmarks"
printf '[apps]\nplaces = ["%s/Projects", "%s/missing"]\n' "$H" "$H" > "$H/.config/ewe/ewe.conf"
printf '{"account_folder": {"path": "%s/Nextcloud"}, "folders": [{"local": "%s/Nextcloud", "name": "Nextcloud"}]}\n' "$H" "$H" \
    > "$H/.local/state/ewe/sync-folders.json"
echo a > "$H/Docs/old.txt"; echo b > "$H/Docs/new.txt"
cat > "$H/.local/share/recently-used.xbel" <<X
<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file://$H/Docs/old.txt" added="2026-01-01T10:00:00Z" modified="2026-01-01T10:00:00Z" visited="2026-01-01T10:00:00Z"/>
  <bookmark href="file://$H/Docs/new.txt" added="2026-11-01T10:00:00.123456Z" modified="2026-11-01T10:00:00Z" visited="2026-11-01T10:00:00Z"/>
  <bookmark href="file://$H/Docs/gone.txt" visited="2026-11-02T10:00:00Z"/>
</xbel>
X
printf '[preferred]\ndefault=hyprland;gtk\norg.freedesktop.impl.portal.FileChooser=ewe;gtk\n' \
    > "$H/.config/xdg-desktop-portal/hyprland-portals.conf"

OUT="$SB/unit.out"
HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_STATE_HOME="$H/.local/state" \
XDG_CURRENT_DESKTOP=Hyprland EWE_PORTAL_MIME_DIRS="$SB/mime" EWE_PORTAL_MEDIA="$SB/media" USER=tester \
python3 -I - "$REPO/bin/ewe-portal" "$H" > "$OUT" 2>&1 <<'PY' || true
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("ewe_portal", sys.argv[1])
spec = importlib.util.spec_from_loader("ewe_portal", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
H = sys.argv[2]

def ok(name, cond):
    print(("PASS " if cond else "FAIL ") + name)

def raises(fn):
    try:
        fn()
    except ValueError:
        return True
    return False

db = m.load_mime_db()
ok("image/* covers every image type", set(m.mime_globs("image/*", db)) == {"*.png", "*.jpg", "*.jpeg"})
ok("text/plain includes its subclasses", set(m.mime_globs("text/plain", db)) == {"*.txt", "*.py"})
ok("an alias resolves", m.mime_globs("image/jpg", db) == ["*.jpg", "*.jpeg"])
ok("octet-stream means everything", m.mime_globs("application/octet-stream", db) == ["*"])

f, i = m.normalize_filters([("PDF", [(1, "application/pdf")]), ("Mixed", [(0, "*.md"), (1, "text/x-python")]),
                            ("Odd", [(1, "x-unknown/thing")])], None, db)
ok("filters: mime and glob mixed", f[1]["globs"] == ["*.md", "*.py"] and f[0]["globs"] == ["*.pdf"])
ok("filters: an unknown type shows everything, not nothing", f[2]["globs"] == ["*"])
ok("filters: the first is current by default", i == 0)
f, i = m.normalize_filters([("PDF", [(1, "application/pdf")])], ("Text", [(0, "*.txt")]), db)
ok("filters: a current filter not in the list is added and picked", len(f) == 2 and i == 1)
f, i = m.normalize_filters([("PDF", [(1, "application/pdf")]), ("Text", [(0, "*.txt")])], ("Text", [(0, "*.txt")]), db)
ok("filters: a listed current filter is found", i == 1)
ok("filters: none at all", m.normalize_filters(None, None, db) == ([], -1))

c = m.normalize_choices([("enc", "Encoding", [("utf8", "UTF-8"), ("l1", "Latin-1")], "bogus"),
                         ("ro", "Open read-only", [], "true")])
ok("choices: an invalid initial falls back to the first option", c[0]["kind"] == "select" and c[0]["value"] == "utf8")
ok("choices: no options = a checkbox", c[1]["kind"] == "toggle" and c[1]["value"] == "true")

ok("ay path: NUL-terminated bytes", m.bytes_path([104, 105, 0]) == "hi")
ok("ay path: absent", m.bytes_path(None) == "")
u = m.path_to_uri("/tmp/a b#c%d/ü.txt")
ok("uri: GLib escaping", u == "file:///tmp/a%20b%23c%25d/%C3%BC.txt")
ok("uri: round trip", m.uri_to_path(u) == "/tmp/a b#c%d/ü.txt")
ok("uri: only local files", m.uri_to_path("sftp://host/x") == "" and m.uri_to_path("file://otherhost/x") == "")

p = m.places()
names = [(x["name"], x["group"]) for x in p]
ok("places: Home first", names[0] == ("Home", "places"))
ok("places: XDG folders, desktop = home skipped", ("Docs", "places") in names and ("Pics", "places") in names
   and sum(1 for x in p if x["path"] == H) == 1)
ok("places: the account folder once", sum(1 for x in p if x["path"].endswith("/Nextcloud")) == 1
   and ("Nextcloud", "cloud") in names)
ok("places: ewe.conf pins (missing ones skipped)", ("Projects", "pinned") in names and not any("missing" in x["path"] for x in p))
ok("places: GTK bookmarks with labels, no duplicates, no remote", ("Work", "pinned") in names
   and sum(1 for x in p if x["path"].endswith("/Docs")) == 1 and not any(x["name"] == "Remote" for x in p))
ok("places: removable drives", ("USBKEY", "drives") in names)

r = m.recent()
ok("recent: newest first, gone files dropped", [os.path.basename(x["path"]) for x in r] == ["new.txt", "old.txt"])

s = m.load_state()
for n in range(105):
    s = m.remember(s, {"key": "app%d" % n, "folder": "/x/%d" % n})
s = m.remember(s, {"key": "app104", "folder": "relative/path", "view": "grid", "hidden": True, "sort": "bogus"})
ok("remember: at most 100 apps, oldest dropped", len(s["folders"]) == 100 and "app0" not in s["folders"])
ok("remember: relative folders, bad sorts ignored", s["folders"]["app104"] == "/x/104" and "sort" not in s
   and s["view"] == "grid" and s["hidden"] is True)
m.save_state(s)
ok("remember: saved and read back", m.load_state()["view"] == "grid")

doc = os.path.join(H, "Docs", "new.txt")
raw, _ = m.normalize_filters([("PDF", [(1, "application/pdf")]), ("Text", [(0, "*.txt")])], None, db)
req = {"kind": "open", "multiple": False, "filter": 0, "files": [],
       "choices": m.normalize_choices([("enc", "Encoding", [("utf8", "UTF-8"), ("l1", "Latin-1")], "utf8")])}
res = m.build_results(req, raw, {"paths": [doc, os.path.join(H, "Docs", "old.txt")], "filter": 1, "choices": {}})
ok("results: one file unless multiple", len(res["uris"]) == 1 and res["uris"][0].endswith("/Docs/new.txt"))
ok("results: unpicked choices keep their value", res["choices"] == [["enc", "utf8"]])
ok("results: the filter goes back exactly as the app sent it", res["current_filter"] == ["Text", [[0, "*.txt"]]])
ok("results: a bad filter index is left out", "current_filter" not in m.build_results(req, raw, {"paths": [doc], "filter": 7})
   and "current_filter" not in m.build_results(req, raw, {"paths": [doc], "filter": True}))
ok("results: missing, relative, empty refused", raises(lambda: m.build_results(req, raw, {"paths": ["/nope/x"]}))
   and raises(lambda: m.build_results(req, raw, {"paths": ["Docs/new.txt"]}))
   and raises(lambda: m.build_results(req, raw, {"paths": []})))
ok("results: a folder pick must be a folder", raises(lambda: m.build_results(dict(req, kind="folder"), raw, {"paths": [doc]}))
   and m.build_results(dict(req, kind="folder"), raw, {"paths": [os.path.join(H, "Docs")]})["uris"][0].endswith("/Docs"))
ok("results: save into a missing folder refused", raises(lambda: m.build_results(dict(req, kind="save"), raw, {"paths": ["/nope/x.txt"]})))
ok("results: save a new name", m.build_results(dict(req, kind="save"), raw, {"paths": [os.path.join(H, "Docs", "brand new.txt")]})["uris"][0]
   .endswith("/Docs/brand%20new.txt"))
sv = m.build_results(dict(req, kind="saves", files=["a.txt", "b c.txt"]), raw, {"folder": os.path.join(H, "Docs")})
ok("results: save several = the folder + each name", [x.rsplit("/", 1)[1] for x in sv["uris"]] == ["a.txt", "b%20c.txt"])
ok("results: open with needs an app", raises(lambda: m.build_results({"kind": "app"}, [], {}))
   and m.build_results({"kind": "app"}, [], {"choice": "org.x.App"}) == {"choice": "org.x.App"})

rq = m.build_request("abc", "save", ["/h", "", "", "Save as", {"current_name": "x.txt", "current_folder": [47, 116, 109, 112, 0]}], db)
rq2 = m.build_request("abc", "open", ["/h", "", "", "Open", {"current_folder": list(b"/nope/gone") + [0]}], db)
ok("request: a folder that is gone is dropped, remembered ones too", rq2["current_folder"] == "" and all(os.path.isdir(v) for v in rq2["remembered"].values()))
ok("request: save carries the name and folder, no recent list", rq["current_name"] == "x.txt" and rq["current_folder"] == "/tmp"
   and rq["recent"] == [] and rq["view"] == "grid")
ra = m.build_request("abc", "app", ["/h", "org.app", "wayland:1", ["a", "b"], {"last_choice": "b", "content_type": "text/plain"}])
ok("request: open with lists the apps", ra["choices"] == ["a", "b"] and ra["last_choice"] == "b" and ra["kind"] == "app")

rt = m.routing()
ok("routing: the user's hyprland-portals.conf sends files to ewe", rt["ewe"] and rt["file_chooser"] == ["ewe", "gtk"]
   and rt["app_chooser"] == ["hyprland", "gtk"])
PY
while IFS= read -r line; do
    case "$line" in
        PASS*) pass=$((pass+1)) ;;
        FAIL*) failn=$((failn+1)); echo "$line" ;;
        *) echo "unit: $line"; failn=$((failn+1)) ;;
    esac
done < "$OUT"

# ── 2. the chain on a private bus ───────────────────────────────────────────
XDP=/usr/lib/xdg-desktop-portal
if ! command -v dbus-run-session >/dev/null || [ ! -x "$XDP" ] || ! command -v busctl >/dev/null; then
    echo "skip: end-to-end (needs dbus-run-session, busctl and $XDP)"
else
    E="$SB/e2e"
    mkdir -p "$E/bin" "$E/portals" "$E/run" "$E/home/Docs"
    chmod 700 "$E/run"
    echo hi > "$E/home/Docs/a report.pdf"
    printf '[portal]\nDBusName=org.freedesktop.impl.portal.desktop.ewe\nInterfaces=org.freedesktop.impl.portal.FileChooser;org.freedesktop.impl.portal.AppChooser;\n' \
        > "$E/portals/ewe.portal"
    # XDG_DESKTOP_PORTAL_DIR also makes the frontend read portals.conf from there only
    printf '[preferred]\ndefault=ewe\n' > "$E/portals/hyprland-portals.conf"
    # the fake shell: FAKE_MODE answer · cancel · missing · lose
    cat > "$E/bin/qs" <<'Q'
#!/usr/bin/env bash
[ "$1" = ipc ] && shift; [ "$1" = --pid ] && shift 2; [ "$1" = call ] && shift
t=$1 fn=$2 arg=${3:-}
echo "$t $fn $arg" >> "$FAKE/calls"
case "$FAKE_MODE:$fn" in
  missing:*) echo "Target not found." ;;
  lose:open) echo ok ;;
  lose:ping) echo unknown ;;
  *:open) echo ok
      ( sleep 0.3
        id=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$arg")
        cp "$arg" "$FAKE/last-request.json"
        busctl --user call org.freedesktop.impl.portal.desktop.ewe /org/ewe/Portal org.ewe.Portal1 Answer ss \
            "$id" "$(cat "$FAKE/answer.json")" > "$FAKE/answer-result" 2>&1 ) >/dev/null 2>&1 & ;;
  *:ping) echo open ;;
  *:close) echo ok ;;
esac
Q
    chmod +x "$E/bin/qs"
    cat > "$E/run.sh" <<'R'
#!/usr/bin/env bash
E=$1; shift
cd "$E"
"$REPO/bin/ewe-portal" serve 2>> "$E/daemon.log" &
for _ in $(seq 50); do busctl --user status org.freedesktop.impl.portal.desktop.ewe >/dev/null 2>&1 && break; sleep 0.1; done
/usr/lib/xdg-desktop-portal -r 2>> "$E/xdp.log" &
for _ in $(seq 50); do busctl --user status org.freedesktop.portal.Desktop >/dev/null 2>&1 && break; sleep 0.1; done
"$REPO/bin/ewe-portal" test "$@"
R
    chmod +x "$E/run.sh"
    e2e() {   # MODE ANSWER-JSON test-args… → the test's JSON in $E/out
        printf '%s' "$2" > "$E/answer.json"
        : > "$E/calls"; rm -f "$E/last-request.json"
        local mode=$1; shift 2
        env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u EWE_QS_IPC \
            REPO="$REPO" FAKE="$E" FAKE_MODE="$mode" PATH="$E/bin:$PATH" HOME="$E/home" XDG_RUNTIME_DIR="$E/run" \
            XDG_CONFIG_HOME="$E/home/.config" XDG_DATA_HOME="$E/home/.local/share" XDG_STATE_HOME="$E/home/.local/state" \
            XDG_CURRENT_DESKTOP=Hyprland XDG_DESKTOP_PORTAL_DIR="$E/portals" EWE_PORTAL_MEDIA="$E/none" \
            dbus-run-session -- "$E/run.sh" "$E" "$@" > "$E/out" 2>/dev/null || true
    }
    jq_() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$E/out" "$1" 2>/dev/null; }

    e2e answer "{\"ok\": true, \"paths\": [\"$E/home/Docs/a report.pdf\"], \"choices\": {\"enc\": \"l1\"}, \"filter\": 0,
                 \"remember\": {\"key\": \"tester\", \"folder\": \"$E/home/Docs\"}}" \
        open --mime "PDF:application/pdf" --filter "Text:*.txt" --choice "enc|Encoding|utf8=UTF-8,l1=Latin-1|utf8" --timeout 15
    check "e2e: a picked file reaches the app as a file URI" \
        '[ "$(jq_ "d[\"response\"], d[\"results\"][\"uris\"][0].endswith(\"/Docs/a%20report.pdf\")")" = "(0, True)" ]'
    check "e2e: choices and the filter come back" \
        '[ "$(jq_ "d[\"results\"][\"choices\"] == [[\"enc\", \"l1\"]] and d[\"results\"][\"current_filter\"] == [\"PDF\", [[1, \"application/pdf\"]]]")" = True ]'
    check "e2e: the shell got the request through IPC verb filepicker open" 'grep -q "^filepicker open " "$E/calls"'
    check "e2e: the request file carried the filter as globs" \
        'python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if \"*.pdf\" in d[\"filters\"][0][\"globs\"] else 1)" "$E/last-request.json"'
    check "e2e: the request file is gone afterwards" '[ -z "$(ls -A "$E/run/ewe-portal" 2>/dev/null)" ]'
    check "e2e: the folder is remembered" 'grep -q "\"tester\"" "$E/home/.local/state/ewe/filepicker.json"'

    e2e cancel '{"ok": false}' save --name "x.txt" --timeout 15
    check "e2e: Cancel = response 1" '[ "$(jq_ "d[\"response\"]")" = "1" ]'

    e2e answer "{\"ok\": true, \"folder\": \"$E/home/Docs\"}" saves --files "one.txt,two.txt" --timeout 15
    check "e2e: save several → one URI per file in the folder" \
        '[ "$(jq_ "[u.rsplit(\"/\",1)[1] for u in d[\"results\"][\"uris\"]] == [\"one.txt\", \"two.txt\"]")" = True ]'

    e2e answer '{"ok": true, "choice": "org.example.Viewer"}' app --direct --choices "org.example.Viewer,org.example.Editor" --timeout 15
    check "e2e: open with → the chosen app (verb appchooser open)" \
        '[ "$(jq_ "d[\"results\"][\"choice\"]")" = "org.example.Viewer" ] && grep -q "^appchooser open " "$E/calls"'

    e2e answer '{"ok": true, "paths": ["relative.txt"]}' open --timeout 6
    check "e2e: an unusable answer keeps the picker open (no reply until the app gives up)" \
        '[ "$(jq_ "d[\"ok\"] is False and d.get(\"error\") == \"timed out\"")" = True ]'

    start=$(date +%s)
    e2e missing '{}' open --timeout 30
    check "e2e: no shell → the GTK backend gets it (here it cannot draw: response 2, no hang)" \
        '[ "$(jq_ "d[\"response\"]")" = "2" ] && [ $(( $(date +%s) - start )) -lt 20 ]'
    check "e2e: the fallback is logged" 'grep -q "GTK dialog for OpenFile — shell: Target not found." "$E/daemon.log"'

    e2e lose '{}' open --timeout 30
    check "e2e: the shell loses the picker → GTK takes over after two pings" \
        '[ "$(jq_ "d[\"response\"]")" = "2" ] && [ "$(grep -c "^filepicker ping " "$E/calls")" -ge 2 ]'
fi

echo "ewe-portal: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
