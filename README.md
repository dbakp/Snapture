# Snapture

**Beautiful screenshots for product people.** Capture an area, window, or full screen, drop it into a polished editor, and copy the finished image to your clipboard in one keystroke — no saving, no uploading.

![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Release](https://img.shields.io/github/v/release/dbakp/Snapture)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)

Snapture lives in your menu bar. Hit a hotkey, select what you want, annotate it, and paste it straight into Slack, Figma, a PR, or a doc. Everything stays on your Mac — it never touches the network.

---

## Download

**[⬇︎ Download the latest release](https://github.com/dbakp/Snapture/releases/latest)** — open the `.dmg` and drag Snapture into Applications.

Requires **macOS 14 or later** · Apple silicon & Intel.

### First launch (one-time)

Snapture is signed but **not notarized by Apple**, so Gatekeeper warns you the first time:

- **macOS 15 / 26 (Sequoia / Tahoe):** try to open Snapture once, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
- **Older macOS:** right-click Snapture → **Open** → **Open**.

You only do this once. On first capture, macOS asks for **Screen Recording** permission (System Settings → Privacy & Security → Screen Recording → enable Snapture) — required for any screenshot tool.

---

## Features

### Capture
- **`⌘⇧2`** — area capture with a crosshair and live dimensions, on any monitor
- **`⌘⇧1`** — window capture with a **live thumbnail of the real window** under your cursor (accurate even when it's hidden behind others), labelled with its app and title
- **`⌃⌘3`** — full screen (the display under your cursor)
- 3-second delayed capture from the menu bar
- Fully multi-monitor aware

### Record GIFs
- **`⌥⌘G`** — drag a region, then record it as an animated GIF
- A quality slider (resolution + frame rate) with a **live size estimate** for your selection
- A **persistent outline** stays around the recording area so you always see what's captured
- Press **Stop** (or `⌥⌘G` again) — record as long as you like; the result is saved and copied to the clipboard

### Compose
- Background presets (gradients + solids) or a custom color
- **Window-chrome framing** — wrap the shot in a macOS titlebar or browser chrome (traffic lights + URL bar) for clean product mockups
- Adjustable padding, corner radius, and drop shadow

### Annotate
- Rectangle, ellipse, triangle, line, **arrow** (full 360° with endpoint handles), **pen**, **text**, **step badges** (auto-incrementing 1·2·3…), **magnifier** loupe (1.2×–8×), **blur / pixelate** for redaction, and **highlight** spotlights
- Per-layer drop shadows; click any layer to grab, move, and resize it; ⇧ locks aspect on images
- Double-click text to edit inline

### Export
- **`⌘C`** copy the composed image to the clipboard — pixel-identical to what you see
- **`⌘S`** save as PNG
- **Drag-out chip** — drag the result straight into another app without saving
- **Copy Text (OCR)** — pull the text out of a screenshot

### App
- Menu-bar app (no Dock clutter) that surfaces in the Dock and ⌘-Tab only while you have an editor open
- Multiple editor windows at once, undo/redo, launch-at-login
- Preferences for capture behavior (auto-copy, shutter sound, cursor) and default look

---

## Keyboard shortcuts

| | |
|---|---|
| Capture area / window / full screen | `⌘⇧2` · `⌘⇧1` · `⌃⌘3` |
| Record GIF | `⌥⌘G` |
| Tools | Select `V` · Crop `C` · Rectangle `R` · Ellipse `O` · Triangle `Y` · Line `L` · Arrow `A` · Pen `P` · Text `T` · Step badge `N` · Magnifier `M` · Blur `B` · Highlight `H` |
| Paste image as layer | `⌘V` |
| Z-order | forward `⌘]` · backward `⌘[` · front `⌘⇧A` · back `⌘⇧B` |
| Delete layer | `⌫` |
| Undo / redo | `⌘Z` / `⌘⇧Z` |
| Copy / save | `⌘C` / `⌘S` |
| Preferences | `⌘,` |

---

## Privacy

Snapture never connects to the internet. Your screenshots never leave your Mac. The only system permission it requests is **Screen Recording**, which macOS requires for any app that captures the screen.

---

## Building from source

```bash
git clone https://github.com/dbakp/Snapture.git
cd Snapture
./build.sh             # debug build → .build/Snapture.app
./build.sh release     # optimized build
./build.sh dmg         # release + distributable Snapture-<version>.dmg
swift test             # logic test suite (19 tests)
open .build/Snapture.app
```

Built with **Swift 6, SwiftUI, ScreenCaptureKit, and Vision**. No third-party Swift dependencies.

<details>
<summary>Packaging the DMG</summary>

`./build.sh dmg` builds the branded installer (app on a pedestal, arrow pointing to an /Applications alias). The window layout is written directly into the DMG's `.DS_Store` via two pure-Python packages — install them once:

```bash
python3 -m pip install --user ds_store mac_alias
```

Without them, the build falls back to a plain DMG (no custom background) and prints the install command.

> **macOS 26.2+ note:** Tahoe's Finder regressed so that a background-image *bookmark* (`pBBk`) record makes the DMG background render blank. `Scripts/dmg_layout.py` deliberately omits it — see [dmgbuild #273](https://github.com/dmgbuild/dmgbuild/issues/273).

The app is ad-hoc signed with a stable identifier-based designated requirement, so the Screen Recording permission survives updates. Add a Developer ID certificate + notarization to remove the Gatekeeper prompt entirely.
</details>

<details>
<summary>Project layout</summary>

```
Sources/Snapture/
├── App/        # @main, menu bar, global hotkeys, preferences, window management
├── Capture/    # ScreenCaptureKit: area + window-pick overlays (multi-display)
├── Editor/     # editor window, canvas, sidebar, state, annotations
└── Export/     # composer (ImageRenderer), clipboard / PNG
```

The same `CompositionView` powers both the live editor and the exported image, so a copy is pixel-identical to what you see. Annotations are stored in a scale-independent coordinate space; arrows/lines encode direction as signed frame sizes (see the `arrowTail` / `arrowTip` accessors in [Annotation.swift](Sources/Snapture/Editor/Annotation.swift) before touching that geometry).
</details>

---

## Roadmap

- Scrolling capture
- Capture-history browser in the menu
- Pin a screenshot as a floating always-on-top window
- Configurable hotkeys
- Notarized distribution

## License

[MIT](LICENSE) © 2026 David Bak Posada
