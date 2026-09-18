#!/usr/bin/env python3
"""Screenshot component previews for side-by-side checks against an implementation.

    pip install playwright && playwright install chromium
    python3 tools/screenshot.py [Name ...]      # all components when no names are given

Writes shots/<Name>-dark.png and shots/<Name>-light.png next to this bundle's view/ folder.
"""
import os, sys
from playwright.sync_api import sync_playwright
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
view = os.path.join(root, "view")
names = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(view) if f.endswith(".html") and f != "index.html")
out = os.path.join(root, "shots"); os.makedirs(out, exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width": 960, "height": 600})
    for n in names:
        for theme in ("dark", "light"):
            pg.goto(f"file://{view}/{n}.html?theme={theme}"); pg.wait_for_timeout(300)
            pg.screenshot(path=os.path.join(out, f"{n}-{theme}.png"), full_page=True)
    b.close()
print("wrote", len(names) * 2, "screenshots to", out)
