#!/usr/bin/env bash
# Every icon codepoint used anywhere must exist in the vendored Lucide face.
#
# This exists because of a real bug: the icon library was swapped and the
# named table in Theme.qml was migrated, but ~30 codepoints hard-coded inside
# QML and Svelte files were not. They did not fail loudly — they silently
# resolved to whatever unrelated glyph now sat at that codepoint, so the
# Power row in Settings rendered the letters "AB". A wrong glyph is invisible
# to every other kind of test, so it gets its own.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
font="$root/dotfiles/quickshell/fonts/Lucide.ttf"
[ -r "$font" ] || { echo "missing $font"; exit 1; }
python3 - "$font" "$root" "$@" <<'PY'
import re, sys, glob, os, logging
logging.disable(logging.WARNING)   # the vendored TTF trips a benign post-table notice
from fontTools.ttLib import TTFont
font, root = sys.argv[1], sys.argv[2]
extra = sys.argv[3:]
cmap = set(TTFont(font).getBestCmap())
roots = [os.path.join(root, "dotfiles/quickshell")] + extra
files = []
for r in roots:
    for ext in ("qml", "svelte", "js", "css"):
        files += glob.glob(os.path.join(r, "**/*." + ext), recursive=True)
bad = 0
for p in sorted(set(files)):
    if "/node_modules/" in p or "/dist/" in p:
        continue
    for i, line in enumerate(open(p, encoding="utf-8", errors="ignore"), 1):
        for m in re.finditer(r'0x([0-9a-fA-F]{4})', line):
            c = int(m.group(1), 16)
            if 0xE000 <= c <= 0xF8FF and c not in cmap:
                print("  MISSING 0x%04X  %s:%d" % (c, os.path.relpath(p, root), i))
                bad += 1
print("no icon codepoint outside the vendored face" if not bad
      else "%d codepoint(s) not in Lucide" % bad)
sys.exit(1 if bad else 0)
PY
