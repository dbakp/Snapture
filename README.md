# Snapture

A native macOS screenshot app for product managers. Capture an area or a window, drop it into a polished editor, copy the result to clipboard in one keystroke.

Built with Swift 6, SwiftUI, ScreenCaptureKit, Vision. macOS 14+.

## Features

**Capture**
- `⌘⇧2` — area capture with crosshair + live dimensions (multi-display)
- `⌘⇧1` — window capture: hover shows a **live thumbnail of the actual window** (captured through the same filter as the real shot, so it's accurate even when the window is hidden behind others), labelled with its app + title; click to capture
- `⌃⌘3` — full screen capture (⌘⇧3 is reserved by macOS for its own screenshot)
- 3-second delayed capture from the menu bar
- Menu bar app (camera viewfinder icon), no dock presence

**Compose**
- Background presets (gradients + solids) and custom solid color
- **Window chrome framing**: wrap the screenshot in a macOS titlebar or browser chrome (traffic lights + URL bar) for product-shot mockups
- Adjustable padding, corner radius, screenshot drop-shadow (radius + opacity)

**Annotate**
- Tools: Select (V) · Crop (C) · Rectangle (R) · Ellipse (O) · Triangle (Y) · Line (L) · Arrow (A) · Pen (P) · Text (T) · Step badge (N) · Magnifier (M) · Blur (B) · Highlight (H)
- **Step badges**: numbered circles that auto-increment — annotate flows 1, 2, 3…
- **Pen**: freehand drawing that moves and scales with its frame
- **Magnifier**: circular loupe that zooms the screenshot under it (1.2×–8×, ring color/width)
- **Blur regions**: gaussian *or* pixelate (mosaic) for redaction
- Highlight: dims everything except punched-out spotlight rects (multiple highlights never stack-dim)
- Per-layer drop shadow (rectangle / ellipse / triangle / image / text / badge / magnifier)
- Arrows & lines: endpoint handles, drag either end, the other pins; full 360° direction
- Click any layer from any tool to grab it; corner handles resize; ⇧ locks image aspect
- Double-click text to edit inline; Enter/Escape/click-outside commits

**Layers**
- `⌘V` pastes any clipboard image as a new layer
- Z-order: `⌘]` forward · `⌘[` backward · `⌘⇧A` front · `⌘⇧B` back
- `⌫` deletes the selected layer

**Undo / redo**
- `⌘Z` / `⌘⇧Z` (or `⌘Y`), depth 80, slider drags collapse to one step

**Export**
- `⌘C` copy composed PNG to clipboard
- `⌘S` save as PNG
- **Drag chip** — drag the composed image straight into Slack / Figma / Finder without saving
- **Copy Text (OCR)** — Vision-based text recognition of the screenshot, copied as plain text

**App**
- Per-capture editor windows (open several at once)
- **Preferences** (menu bar → Preferences, `⌘,`) — two tabs:
  - *Capture*: auto-copy to clipboard on capture, shutter sound, include the mouse cursor, launch at login
  - *Appearance*: default background, default window frame, drop shadow, padding, corner radius

## Build & run

```bash
./build.sh             # debug build
./build.sh release     # optimized
./build.sh dmg         # release + distributable Snapture-<version>.dmg

open .build/Snapture.app
swift test             # 15-test logic suite
```

## Distribution

`./build.sh dmg` produces a polished `Snapture-<version>.dmg`: the app on a
pedestal, an arrow pointing to an /Applications alias, install instructions
("Read Me - First Launch.txt"), and a branded background.

The fancy window layout is written straight into the DMG's `.DS_Store` (via the
`ds_store` + `mac_alias` Python packages) rather than by scripting Finder —
install them once:

```bash
python3 -m pip install --user ds_store mac_alias
```

If they're missing, `build.sh` falls back to a plain (background-less) DMG and
prints the install command. Note: macOS **26.2+ (Tahoe)** regressed Finder so
that a background-image *bookmark* (`pBBk`) record makes the background render
blank; `Scripts/dmg_layout.py` deliberately omits it (see the script header and
[dmgbuild #273](https://github.com/dmgbuild/dmgbuild/issues/273)).

The app is **ad-hoc signed, not notarized**. People who download the DMG will
hit Gatekeeper once: on macOS 15+ they must open the app once, then approve it
under System Settings → Privacy & Security → "Open Anyway"; on older macOS,
right-click → Open → Open. The bundled READ ME explains this. The signature
uses a stable identifier-based designated requirement, so the Screen Recording
permission survives app updates. To remove the Gatekeeper friction entirely,
sign with a Developer ID certificate and notarize (see Roadmap).

### First-launch permission

The first capture prompts for **Screen Recording** permission:

> System Settings → Privacy & Security → Screen Recording → enable **Snapture**

Then re-launch (`pkill Snapture && open .build/Snapture.app`).

Note: ⌘⇧1 / ⌘⇧2 are global hotkeys. Window capture excludes Snapture's own windows from the picker. Launch-at-login works best when the app is moved to /Applications.

## Project layout

```
Sources/Snapture/
├── App/                          # @main, menu bar, hotkeys, preferences
├── Capture/                      # ScreenCaptureKit: area, window pick overlays
├── Editor/                       # editor window, canvas, sidebar, state, annotations
└── Export/                       # composer (ImageRenderer), clipboard/PNG, OCR lives in EditorView
```

The same `CompositionView` powers the live editor preview and the exported image — pixel parity guaranteed. Arrows/lines store direction as signed frame sizes; see the `arrowTail`/`arrowTip` accessors in [Annotation.swift](Sources/Snapture/Editor/Annotation.swift) before touching that geometry.

## Roadmap (not yet built)

- Screen recording → MP4 / GIF
- Scrolling capture
- Capture history browser (recent screenshots in the menu)
- Pin screenshot as floating always-on-top window
- Cloud upload + shareable links
- Configurable hotkeys UI
- Social-size canvas presets (16:9, 4:3, X/Twitter card)
- Notarized .dmg distribution
