#!/usr/bin/env bash
# Build Snapture as a proper .app bundle with ad-hoc code signing.
# Usage: ./build.sh           (debug build, fast)
#        ./build.sh release   (release build, optimized)
#        ./build.sh dmg       (release build + distributable Snapture-<version>.dmg)

set -euo pipefail

MODE="${1:-debug}"
APP_NAME="Snapture"
BUNDLE_ID="com.snapture.app"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

CONFIG="$MODE"
if [ "$MODE" = "dmg" ]; then CONFIG="release"; fi

echo "→ Building Snapture ($CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    swift build -c release
    BIN_PATH=$(swift build -c release --show-bin-path)
else
    swift build
    BIN_PATH=$(swift build --show-bin-path)
fi

echo "→ Assembling .app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_DIR/Contents/MacOS/"
cp Info.plist            "$APP_DIR/Contents/"

# Copy SwiftPM-processed resources (bundle) if any
if [ -d "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" "$APP_DIR/Contents/Resources/"
fi

# Embed the PkgInfo file (some macOS APIs check for this)
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# App icon
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/"
fi

echo "→ Ad-hoc signing with stable identity…"
# The explicit identifier-based designated requirement is what keeps macOS
# permissions (Screen Recording) stable across rebuilds. Without it, ad-hoc
# signatures get a cdhash-based requirement that changes with every build,
# and TCC treats each build as a brand-new app and re-prompts.
codesign --force --sign - \
    --identifier "$BUNDLE_ID" \
    --requirements '=designated => identifier "'"$BUNDLE_ID"'"' \
    --entitlements Snapture.entitlements \
    --options runtime \
    "$APP_DIR" 2>&1 | grep -v "replacing existing signature" || true

echo ""
echo "✓ Built $APP_DIR"

if [ "$MODE" = "dmg" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
    DMG_NAME="$APP_NAME-$VERSION.dmg"
    VOL_NAME="$APP_NAME"
    README_NAME="Read Me - First Launch.txt"
    STAGING="$BUILD_DIR/dmg-staging"
    RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"

    echo "→ Staging DMG contents…"
    rm -rf "$STAGING" "$DMG_NAME" "$RW_DMG"
    mkdir -p "$STAGING/.background"
    swift Scripts/generate_dmg_background.swift "$STAGING/.background/background.png" > /dev/null
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"

    cat > "$STAGING/$README_NAME" << 'INSTALLEOF'
INSTALLING SNAPTURE
===================

1. Drag Snapture onto the Applications folder (follow the arrow).

2. Open Snapture from /Applications.

   The FIRST time, macOS will warn that Snapture is from an unidentified
   developer (it isn't notarized by Apple). To open it anyway:

   • macOS 15 (Sequoia) and later:
     Attempt to open Snapture once, then go to
     System Settings → Privacy & Security, scroll down,
     and click "Open Anyway" next to the Snapture message.

   • Earlier macOS versions:
     Right-click (or Control-click) Snapture.app → Open → Open.

   You only need to do this once.

3. Snapture appears in your MENU BAR (camera icon) — there is no dock icon.
   A welcome window explains the basics and asks for the Screen Recording
   permission Snapture needs to take screenshots.

Hotkeys: ⌘⇧2 capture area · ⌘⇧1 capture window · ⌃⌘3 full screen

Snapture never connects to the internet. Your screenshots stay on your Mac.
INSTALLEOF

    echo "→ Creating writable image…"
    # Detach any stale Snapture volume so the new one mounts under the real name.
    for v in /Volumes/"$VOL_NAME"*; do
        [ -d "$v" ] && hdiutil detach "$v" -force > /dev/null 2>&1 || true
    done
    hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" -fs HFS+ \
        -format UDRW -ov "$RW_DMG" > /dev/null

    echo "→ Writing window layout (background + icon positions)…"
    ATTACH_OUT=$(hdiutil attach "$RW_DMG" -nobrowse -noautoopen)
    DEV_NODE=$(echo "$ATTACH_OUT" | egrep '^/dev/disk[0-9]+' | head -1 | awk '{print $1}')
    MOUNT_PT=$(echo "$ATTACH_OUT" | grep -o '/Volumes/.*' | head -1)

    # Writes .DS_Store directly via ds_store/mac_alias. Critically it omits the
    # pBBk bookmark, which breaks backgrounds on macOS 26.2+ (see dmg_layout.py).
    if python3 Scripts/dmg_layout.py "$MOUNT_PT"; then
        echo "  ✓ layout applied"
    else
        echo "  ⚠ Could not write the window layout (need ds_store + mac_alias):"
        echo "      python3 -m pip install --user ds_store mac_alias"
        echo "    The arrow background is bundled either way."
    fi
    sync
    hdiutil detach "$DEV_NODE" > /dev/null 2>&1 || \
        { sleep 1; hdiutil detach "$DEV_NODE" -force > /dev/null 2>&1; } || true

    echo "→ Compressing…"
    hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_NAME" > /dev/null
    hdiutil verify "$DMG_NAME" > /dev/null
    rm -rf "$STAGING" "$RW_DMG"
    echo "✓ Packaged $DMG_NAME ($(du -h "$DMG_NAME" | cut -f1 | xargs))"
else
    echo ""
    echo "Run it with:"
    echo "  open $APP_DIR"
    echo ""
    echo "The first capture will prompt for Screen Recording permission."
    echo "Grant it in System Settings → Privacy & Security → Screen Recording,"
    echo "then re-launch the app."
fi
