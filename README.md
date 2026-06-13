# Snapture

A native macOS screenshot app for product managers. Capture an area or a window, drop it into a polished editor, copy the result to clipboard in one keystroke.

Built with Swift 6, SwiftUI, ScreenCaptureKit, Vision. macOS 14+.

## Features

**Capture**
- `⌘⇧2` — area capture with crosshair + live dimensions (multi-display)
- `⌘⇧1` — window capture: hover highlights the window under the cursor (with its title), click to capture
- Full screen and 3-second delayed capture from the menu bar
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
- Launch at login (Preferences)
- Per-capture editor windows (open several at once)

## Build & run

```bash
./build.sh             # debug build
./build.sh release     # optimized
./build.sh dmg         # release + distributable Snapture-<version>.dmg

open .build/Snapture.app
swift test             # 15-test logic suite
```

## Distribution

`./build.sh dmg` produces `Snapture-<version>.dmg` containing the app, an
/Applications alias, and install instructions ("READ ME FIRST.txt").

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
