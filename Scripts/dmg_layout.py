#!/usr/bin/env python3
"""Write the Snapture DMG window's .DS_Store: picture background + icon layout.

CRITICAL: this deliberately does NOT write a `pBBk` background-bookmark record.
macOS 26.2+ (Tahoe) Finder regressed so that the *presence* of the background
bookmark BREAKS background rendering — the window comes up blank. The fix
(dmgbuild PR #275, issue #273) is to emit only the legacy `backgroundImageAlias`
inside the `icvp` record. See https://github.com/dmgbuild/dmgbuild/issues/273

Everything else mirrors what dmgbuild writes (icvp view options, icvl view
style, bwsp window bounds, per-item Iloc positions).

Usage: dmg_layout.py <mount_point>
Requires: ds_store, mac_alias  (pip install --user ds_store mac_alias)
"""
import os
import sys

from ds_store import DSStore
from mac_alias import Alias

WIDTH, HEIGHT = 600, 420        # background/content size in points
TITLEBAR = 28                   # added to the frame so content == 420pt
ICON_SIZE = 112

POSITIONS = {
    "Snapture.app": (150, 185),
    "Applications": (450, 185),
    "Read Me - First Launch.txt": (300, 330),
}


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: dmg_layout.py <mount_point>", file=sys.stderr)
        return 2
    mount = sys.argv[1]
    bg = os.path.join(mount, ".background", "background.png")
    if not os.path.exists(bg):
        print(f"background not found: {bg}", file=sys.stderr)
        return 1

    alias = Alias.for_file(bg)
    bounds = "{{200, 120}, {%d, %d}}" % (WIDTH, HEIGHT + TITLEBAR)
    ds_path = os.path.join(mount, ".DS_Store")

    with DSStore.open(ds_path, "w+") as d:
        d["."]["vSrn"] = ("long", 1)
        d["."]["bwsp"] = {
            "WindowBounds": bounds,
            "ContainerShowSidebar": False,
            "PreviewPaneVisibility": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
            "ShowStatusBar": False,
            "ShowTabView": False,
            "ShowToolbar": False,
            "SidebarWidth": 0,
        }
        d["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,                     # 2 = picture
            "backgroundImageAlias": alias.to_bytes(),
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
            "iconSize": float(ICON_SIZE),
            "gridSpacing": 100.0,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "textSize": 12.0,
            "labelOnBottom": True,
            "showItemInfo": False,
            "showIconPreview": True,
            "scrollPositionX": 0.0,
            "scrollPositionY": 0.0,
            "arrangeBy": "none",
        }
        d["."]["icvl"] = ("type", "icnv")            # icon view style
        # NO d["."]["pBBk"] — the bookmark breaks backgrounds on macOS 26.2+.
        for name, (x, y) in POSITIONS.items():
            d[name]["Iloc"] = (x, y)

    print("✓ .DS_Store written (picture background, no pBBk; icon positions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
