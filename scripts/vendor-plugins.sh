#!/usr/bin/env bash
# vendor-plugins.sh — refresh the first-party plugins the payload ships
# (plugins/<id>/) from their own repositories, and record what was vendored
# in plugins/bundle.json (repo, commit, version — plus the `default` and
# `migrate` flags, which are kept as they are). They are copies, not
# submodules: `git archive` (release.sh) and the PKGBUILD ship the tree as
# is, and a submodule would arrive empty. Run before a release that should
# carry newer plugin versions; commit the result.
#
# The list of plugins IS bundle.json — add an entry there (id, repo, flags)
# and run this script to vendor it.
#
#   scripts/vendor-plugins.sh                 # from ../ewe-plugin-<name> checkouts
#   scripts/vendor-plugins.sh --clone         # fresh clones of each repo instead
#   scripts/vendor-plugins.sh ewe.media       # only these ids
#   scripts/vendor-plugins.sh --allow-dirty   # vendor a checkout with uncommitted
#                                             # changes (the recorded commit is
#                                             # then marked "-dirty")
#   EWE_PLUGIN_SRC_DIR=/path/to/Projects/ewe scripts/vendor-plugins.sh
#                                             # where the ewe-plugin-<name> checkouts
#                                             # live (default: beside this repo — a
#                                             # worktree under .wt/ needs this)
set -euo pipefail
cd "$(dirname "$0")/.."
BUNDLE=plugins/bundle.json
SRC_DIR="${EWE_PLUGIN_SRC_DIR:-..}"
[ -f "$BUNDLE" ] || { echo "no $BUNDLE — nothing to vendor" >&2; exit 1; }

CLONE=0; DIRTY=0; ONLY=()
for a in "$@"; do
    case "$a" in
        --clone) CLONE=1 ;;
        --allow-dirty) DIRTY=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*) echo "unknown flag: $a" >&2; exit 2 ;;
        *) ONLY+=("$a") ;;
    esac
done

# id<TAB>repo per bundle entry
entries() {
    python3 - "$BUNDLE" <<'EOF'
import json, sys
j = json.load(open(sys.argv[1]))
for pid, m in sorted((j.get("plugins") or {}).items()):
    print("%s\t%s" % (pid, (m or {}).get("repo") or ""))
EOF
}

record() {   # record <id> <commit> <version>
    python3 - "$BUNDLE" "$1" "$2" "$3" <<'EOF'
import json, sys
path, pid, commit, version = sys.argv[1:5]
j = json.load(open(path))
m = j.setdefault("plugins", {}).setdefault(pid, {})
m["commit"] = commit
m["version"] = version
m.setdefault("default", False)
m.setdefault("migrate", False)
j["plugins"] = dict(sorted(j["plugins"].items()))
with open(path, "w") as f:
    json.dump(j, f, indent=2)
    f.write("\n")
EOF
}

n=0
while IFS=$'\t' read -r id repo; do
    [ -n "$id" ] || continue
    if [ ${#ONLY[@]} -gt 0 ]; then
        skip=1; for o in "${ONLY[@]}"; do [ "$o" = "$id" ] && skip=0; done
        [ $skip = 1 ] && continue
    fi
    name="${id#ewe.}"
    tmp=""
    if [ "$CLONE" = 1 ]; then
        [ -n "$repo" ] || { echo "$id: no repo in $BUNDLE — cannot --clone" >&2; exit 1; }
        tmp="$(mktemp -d)"
        git clone -q --depth 1 "$repo" "$tmp/$id"
        src="$tmp/$id"
    else
        src="$SRC_DIR/ewe-plugin-$name"
        [ -f "$src/manifest.json" ] || { echo "$id: no $src checkout — use --clone, or EWE_PLUGIN_SRC_DIR=<dir>" >&2; exit 1; }
        # a release must be reproducible from the recorded commit: refuse a
        # tree with uncommitted changes unless told otherwise
        if [ -n "$(git -C "$src" status --porcelain 2>/dev/null)" ]; then
            if [ "$DIRTY" = 1 ]; then
                echo "$id: $src has uncommitted changes (--allow-dirty: vendoring anyway)" >&2
            else
                echo "$id: $src has uncommitted changes — commit them, or pass --allow-dirty" >&2
                exit 1
            fi
        fi
    fi
    commit="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
    [ "$DIRTY" = 1 ] && [ -n "$(git -C "$src" status --porcelain 2>/dev/null)" ] && commit="$commit-dirty"
    # replace the vendored copy wholesale (python: no shell rm -r in a release script)
    python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "plugins/$id"
    mkdir -p "plugins/$id"
    # everything but git/dev files — the manifest, the QML, the scripts, the licence
    (cd "$src" && tar --exclude=.git --exclude='*.bak.*' --exclude=node_modules --exclude=__pycache__ -cf - .) | (cd "plugins/$id" && tar -xf -)
    v="$(python3 -c "import json;print(json.load(open('plugins/$id/manifest.json'))['version'])")"
    bin/ewe-plugin validate "plugins/$id" --first-party >/dev/null || { echo "$id: the vendored copy does not validate" >&2; exit 1; }
    record "$id" "$commit" "$v"
    echo "vendored $id $v (${commit:0:7})"
    n=$((n+1))
    [ -n "$tmp" ] && python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$tmp"
done < <(entries)
[ "$n" -gt 0 ] || { echo "nothing vendored (ids given do not match $BUNDLE?)" >&2; exit 1; }
