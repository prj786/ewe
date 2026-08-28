#!/usr/bin/env python3
"""google-auth.py — now a shim. The OAuth broker was promoted to `ewe-auth`
(RFC-002): one Google identity for the shell, Komble and future apps. This
path keeps answering for anything that still calls it; resolution through
the config farm reaches the right copy on every install type."""
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
for cand in (os.path.normpath(os.path.join(here, "..", "..", "..", "bin", "ewe-auth")),
             os.path.expanduser("~/.config/quickshell/../../bin/ewe-auth"),
             "/usr/bin/ewe-auth"):
    if os.path.exists(cand):
        os.execv(sys.executable, [sys.executable, cand] + sys.argv[1:])
print('{"ok": false, "error": "ewe-auth not found"}')
