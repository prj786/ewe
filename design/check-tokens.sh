#!/usr/bin/env bash
# The token file is authored once (ewe/design/tokens.css) and copied into each
# app repo as src/tokens.css. Separate repos cannot share a file, so this is
# what stops the copies drifting: run it with the sibling checkouts present.
#
#   ./design/check-tokens.sh [path-to-projects-dir]
#
# Checks BOTH halves: tokens.css (the palette + shape) and components.css
# (the controls built from them).
#
# Exit 0 = every copy matches. Exit 1 = a copy drifted (it prints the diff).
set -uo pipefail
cd "$(dirname "$0")/.."
FILES="tokens.css components.css"
ROOT="${1:-..}"
fail=0

for f in $FILES; do
    [ -r "design/$f" ] || { echo "missing design/$f"; exit 1; }
done

for app in ewe-settings ewe-sync komble-arch; do
    for f in $FILES; do
        src="design/$f"; copy="$ROOT/$app/src/$f"
        if [ ! -r "$copy" ]; then
            echo "MISSING  $app/src/$f — copy $src into it"
            fail=1
        elif diff -q "$src" "$copy" >/dev/null; then
            echo "ok       $app/$f"
        else
            echo "DRIFTED  $app/src/$f:"
            diff -u "$src" "$copy" | sed 's/^/    /'
            fail=1
        fi
    done
done

[ "$fail" = 0 ] && echo "every copy matches design/"
exit $fail
