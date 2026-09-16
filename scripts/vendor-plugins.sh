#!/usr/bin/env bash
# vendor-plugins.sh — refresh the first-party plugins the payload ships
# (plugins/<id>/) from their own repositories. They are copies, not
# submodules: `git archive` (release.sh) and the PKGBUILD ship the tree as
# is, and a submodule would arrive empty. Run before a release that should
# carry newer plugin versions; commit the result.
#
#   scripts/vendor-plugins.sh                # from ../ewe-plugin-<name> checkouts
#   scripts/vendor-plugins.sh --clone        # fresh clones from GitHub instead
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS=(clipboard screenshot passwords)
for name in "${PLUGINS[@]}"; do
    id="ewe.$name"
    if [ "${1:-}" = "--clone" ]; then
        tmp="$(mktemp -d)"
        git clone -q --depth 1 "https://github.com/prj786/ewe-plugin-$name.git" "$tmp/$id"
        src="$tmp/$id"
    else
        src="../ewe-plugin-$name"
        [ -f "$src/manifest.json" ] || { echo "no $src checkout — use --clone" >&2; exit 1; }
    fi
    # replace the vendored copy wholesale (python: no shell rm -r in a release script)
    python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "plugins/$id"
    mkdir -p "plugins/$id"
    # everything but git/dev files — the manifest, the QML, the scripts, the licence
    (cd "$src" && tar --exclude=.git --exclude='*.bak.*' --exclude=node_modules --exclude=__pycache__ -cf - .) | (cd "plugins/$id" && tar -xf -)
    v="$(python3 -c "import json;print(json.load(open('plugins/$id/manifest.json'))['version'])")"
    echo "vendored $id $v"
    if [ "${1:-}" = "--clone" ]; then python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$tmp"; fi
done
