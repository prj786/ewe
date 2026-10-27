#!/usr/bin/env bash
# update.sh (0.35.3): a tarball install — what get.sh leaves in
# ~/.local/share/ewe, no .git — follows the newest GitHub release; a git clone
# still follows origin; a pacman install is pointed at pacman. Everything runs
# in a sandbox with a fake curl (the release API + the artefact from files), a
# fake pacman, systemctl and sudo on PATH, and a stub install.sh that only
# records it was called — the host's ewe.service and ~/.config are never
# touched. Before 0.35.3 a tarball install answered "up to date" for ever.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT=$PWD
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

for t in tar zstd python3 git; do
    command -v "$t" >/dev/null 2>&1 || { echo "skip: needs $t"; exit 0; }
done

bash -n update.sh && ok "update.sh parses" || no "update.sh does not parse"

SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/log"
export PATH="$SB/bin:$PATH" FAKE_LOG="$SB/log"

# ── the fakes ─────────────────────────────────────────────────────────────────
cat >"$SB/bin/curl" <<'EOF'
#!/usr/bin/env bash
# GitHub, from files: the release API answers $FAKE_API, the artefact is $FAKE_TARBALL
out=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift ;;
        --max-time) shift ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
echo "curl $url" >>"$FAKE_LOG/curl"
[ "${FAKE_OFFLINE:-0}" = 1 ] && exit 6
case "$url" in
    *api.github.com/repos/prj786/ewe/releases*) cat "$FAKE_API" ;;
    *.tar.zst) cp "$FAKE_TARBALL" "$out" ;;
    *) exit 22 ;;
esac
EOF
cat >"$SB/bin/pacman" <<'EOF'
#!/usr/bin/env bash
# -Qq ewe: installed only when the test says so; -Q ewe: its version
[ "${FAKE_PKG:-0}" = 1 ] || exit 1
[ "$1" = -Q ] && echo "ewe 0.35.0beta-1"
exit 0
EOF
cat >"$SB/bin/checkupdates" <<'EOF'
#!/usr/bin/env bash
# pacman-contrib's listing: "name old -> new"; exit 2 = nothing to update
if [ "${FAKE_PKG_NEW:-0}" = 1 ]; then
    echo "ewe 0.35.0beta-1 -> 0.35.2beta-1"
    echo "zstd 1.5.7-1 -> 1.5.8-1"
    exit 0
fi
exit 2
EOF
cat >"$SB/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$FAKE_LOG/systemctl"
exit 0
EOF
cat >"$SB/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -n ] && exit 0
exec "$@"
EOF
chmod +x "$SB/bin/"*

stub_install() {   # stub_install <dir> — an install.sh that only records the call
    cat >"$1/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "install.sh $* (VERSION $(cat VERSION))" >>"$FAKE_LOG/install"
exit 0
EOF
}

# the release artefact, as release.sh builds it: ewe-<VERSION>/ prefix
REL=0.35.2-beta
mkdir -p "$SB/rel/ewe-$REL/lib"
echo "$REL" >"$SB/rel/ewe-$REL/VERSION"
echo "shipped" >"$SB/rel/ewe-$REL/lib/new-file.sh"
cp update.sh "$SB/rel/ewe-$REL/update.sh"
stub_install "$SB/rel/ewe-$REL"
tar --zstd -cf "$SB/ewe-$REL.tar.zst" -C "$SB/rel" "ewe-$REL"
export FAKE_TARBALL="$SB/ewe-$REL.tar.zst"
export FAKE_API="$SB/api.json"
cat >"$FAKE_API" <<EOF
[{"tag_name": "v$REL", "prerelease": true,
  "assets": [{"name": "ewe-$REL.tar.zst",
              "browser_download_url": "https://github.com/prj786/ewe/releases/download/v$REL/ewe-$REL.tar.zst"}]}]
EOF

# ── the version order ─────────────────────────────────────────────────────────
# shellcheck disable=SC1090
source <(sed -n '/^newer() {/,/^}/p' update.sh)
newer_is() {   # newer_is <expected 0|1> A B
    newer "$2" "$3"; local rc=$?
    [ "$rc" = "$1" ] && ok "newer $2 $3 → $rc" || no "newer $2 $3 → $rc (want $1)"
}
newer_is 0 0.35.2-beta 0.35.0-beta
newer_is 0 0.35.10-beta 0.35.9-beta
newer_is 0 0.36.0-alpha 0.35.9-beta
newer_is 0 0.35.2 0.35.2-beta
newer_is 0 0.35.2-rc 0.35.2-beta
newer_is 1 0.35.2-beta 0.35.2
newer_is 1 0.35.0-beta 0.35.2-beta
newer_is 1 0.35.2-beta 0.35.2-beta

# ── a tarball install ─────────────────────────────────────────────────────────
T="$SB/tarball"; mkdir -p "$T/dotfiles/hypr/generated"
echo 0.35.0-beta >"$T/VERSION"
echo "mine" >"$T/dotfiles/hypr/generated/user.lua"       # runtime state inside the tree
cp update.sh "$T/update.sh"; stub_install "$T"

out=$(bash "$T/update.sh" --check); rc=$?
[ "$rc" = 10 ] && ok "tarball --check: exit 10 (update available)" || no "tarball --check: exit $rc, want 10: $out"
[[ "$out" == *"0.35.0-beta → $REL"* ]] && ok "tarball --check names both versions" || no "tarball --check output: $out"

out=$(bash "$T/update.sh" --check --json); rc=$?
[ "$rc" = 10 ] && ok "tarball --check --json: exit 10" || no "tarball --check --json: exit $rc"
python3 - "$out" "$REL" <<'PY' && ok "tarball --check --json: the check event Komble reads" || no "tarball --check --json event: $out"
import json, sys
lines = [json.loads(l) for l in sys.argv[1].splitlines() if l.strip()]
assert len(lines) == 1, lines
e = lines[0]
assert e["event"] == "check" and e["updateAvailable"] is True, e
assert e["local"] == "0.35.0-beta" and e["version"] == "0.35.0-beta", e
assert e["remote"] == sys.argv[2] and e["behind"] == 1 and e["dirty"] is False, e
assert e["install"] == "tarball", e
PY

: >"$FAKE_LOG/install"; : >"$FAKE_LOG/systemctl"
out=$(bash "$T/update.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "tarball run: exit 0" || no "tarball run: exit $rc: $out"
[ "$(cat "$T/VERSION")" = "$REL" ] && ok "tarball run: VERSION is now $REL" || no "tarball run: VERSION $(cat "$T/VERSION")"
[ -f "$T/lib/new-file.sh" ] && ok "tarball run: the release's files are unpacked" || no "tarball run: new file missing"
[ "$(cat "$T/dotfiles/hypr/generated/user.lua")" = mine ] && ok "tarball run: runtime state inside the tree survives" || no "tarball run: user.lua clobbered"
grep -q -- "install.sh --yes (VERSION $REL)" "$FAKE_LOG/install" && ok "tarball run: install.sh --yes ran on the new tree" || no "tarball run: install log: $(cat "$FAKE_LOG/install")"
grep -q -- "--user restart ewe.service" "$FAKE_LOG/systemctl" && ok "tarball run: the shell is restarted" || no "tarball run: systemctl log: $(cat "$FAKE_LOG/systemctl")"
[[ "$out" == *"now at $REL"* ]] && ok "tarball run: reports the new version" || no "tarball run output: $out"

out=$(bash "$T/update.sh" --check); rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"up to date ($REL"* ]] && ok "tarball --check after: up to date, exit 0" || no "tarball --check after: exit $rc: $out"

: >"$FAKE_LOG/install"; : >"$FAKE_LOG/curl"
out=$(bash "$T/update.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"already at $REL"* ]] && ok "tarball run when current: no download, exit 0" || no "tarball run when current: exit $rc: $out"
grep -q '\.tar\.zst' "$FAKE_LOG/curl" && no "tarball run when current: downloaded the artefact again" || ok "tarball run when current: the artefact is not downloaded again"
grep -q -- "install.sh --yes" "$FAKE_LOG/install" && ok "tarball run when current: still converges" || no "tarball run when current: install.sh not run"

out=$(FAKE_OFFLINE=1 bash "$T/update.sh" --check 2>&1); rc=$?
[ "$rc" = 1 ] && [[ "$out" == *GitHub* ]] && ok "tarball --check offline: exit 1, says so" || no "tarball --check offline: exit $rc: $out"
out=$(FAKE_OFFLINE=1 bash "$T/update.sh" --check --json 2>&1); rc=$?
[ "$rc" = 1 ] && [[ "$out" == *'"reason": "offline"'* ]] && ok "tarball --check --json offline: an error event, not 'up to date'" || no "tarball --check --json offline: exit $rc: $out"

# ── a pacman install ──────────────────────────────────────────────────────────
out=$(FAKE_PKG=1 bash "$T/update.sh" --check); rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"up to date (ewe 0.35.0beta-1"* ]] && [[ "$out" == *"pacman -Syu"* ]] \
  && ok "package --check: up to date, points at pacman, exit 0" || no "package --check: exit $rc: $out"
out=$(FAKE_PKG=1 FAKE_PKG_NEW=1 bash "$T/update.sh" --check); rc=$?
[ "$rc" = 10 ] && [[ "$out" == *"ewe 0.35.0beta-1 → 0.35.2beta-1"* ]] && [[ "$out" == *"pacman -Syu"* ]] \
  && ok "package --check: a newer package in the repository → exit 10" || no "package --check with a newer package: exit $rc: $out"
out=$(FAKE_PKG=1 FAKE_PKG_NEW=1 bash "$T/update.sh" --check --json); rc=$?
[ "$rc" = 10 ] && [[ "$out" == *'"updateAvailable": true'* ]] && [[ "$out" == *'"remote": "0.35.2beta-1"'* ]] \
  && [[ "$out" == *'"install": "package"'* ]] && ok "package --check --json: updateAvailable, remote = the package version" \
  || no "package --check --json: exit $rc: $out"
: >"$FAKE_LOG/install"
out=$(FAKE_PKG=1 FAKE_PKG_NEW=1 bash "$T/update.sh" 2>&1); rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"pacman -Syu"* ]] && [[ "$out" == *"0.35.2beta-1"* ]] \
  && ok "package run: refuses, names the waiting package, exit 1" || no "package run: exit $rc: $out"
[ -s "$FAKE_LOG/install" ] && no "package run: install.sh ran" || ok "package run: nothing touched"

# ── a git clone ───────────────────────────────────────────────────────────────
: >"$FAKE_LOG/curl"
G() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
mkdir -p "$SB/seed"; echo 0.35.0-beta >"$SB/seed/VERSION"; cp update.sh "$SB/seed/"; stub_install "$SB/seed"
( cd "$SB/seed" && G init -q && G add -A && G commit -qm seed ) || no "git seed"
G clone -q --bare "$SB/seed" "$SB/origin.git"
G clone -q "$SB/origin.git" "$SB/clone"
( cd "$SB/seed" && G remote add origin "$SB/origin.git" && echo 0.35.1-beta >VERSION && G commit -qam bump && G push -q origin main ) || no "git upstream commit"

out=$(bash "$SB/clone/update.sh" --check); rc=$?
[ "$rc" = 10 ] && [[ "$out" == *"1 commit(s) behind"* ]] && ok "clone --check: 1 commit behind, exit 10" || no "clone --check: exit $rc: $out"
out=$(bash "$SB/clone/update.sh" --check --json); rc=$?
[[ "$out" == *'"install": "git"'* ]] && ok "clone --check --json: install=git" || no "clone --check --json: $out"
: >"$FAKE_LOG/install"
out=$(bash "$SB/clone/update.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(cat "$SB/clone/VERSION")" = 0.35.1-beta ] && ok "clone run: pulled, exit 0" || no "clone run: exit $rc, VERSION $(cat "$SB/clone/VERSION"): $out"
grep -q -- "install.sh --yes (VERSION 0.35.1-beta)" "$FAKE_LOG/install" && ok "clone run: converges on the pulled tree" || no "clone run: install log: $(cat "$FAKE_LOG/install")"
grep -q 'api.github.com' "$FAKE_LOG/curl" && no "clone: asked GitHub's release API" || ok "clone: never asks the release API"

cd "$REPO_ROOT" || exit 1
exit $fail
