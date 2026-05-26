# Glean

A macOS "dynamic island"–style floating widget for drag-and-drop access to your Pinterest pins from anywhere.

A small pill sits at the top-center of your screen, always on top, never stealing focus. Hover it and it springs open into a scrollable grid of your pins; drag any pin out and it lands as a real image file in whatever you're working in — Figma, Finder, a chat input, etc.

## Features

- Floating, non-activating panel — doesn't take focus from your current app
- Hover to expand into a vertical grid; filter by board
- Drag a pin out as a full-resolution image file (Finder, Figma, Pixelmator, Electron/web apps like the Claude desktop app, Terminal)
- **⌥⌘B** to hide/show the island
- Picks up newly added pins on open; a ↻ button does a full re-sync (moved pins, new boards)

## Requirements

macOS 14+. Built with Swift 6 / SwiftUI + AppKit, no third-party dependencies.

## Install (prebuilt)

Glean is **not code-signed or notarized**, so macOS Gatekeeper will block it on first open. That's expected.

1. Download `Glean.app.zip`, unzip, and move `Glean.app` to `/Applications`.
2. First launch: **right-click the app → Open**, then confirm in the dialog. (Double-clicking just shows "can't be opened.")
   - Or from Terminal: `xattr -dr com.apple.quarantine /Applications/Glean.app`
3. A Pinterest login window appears on first run. Sign in normally (the QR-code option works if Google login is blocked in the embedded webview). Your session cookies are stored locally (Keychain + the app's WebKit store) and reused after that.

## Build from source

```sh
swift build -c release      # or: ./rebuild.sh release  (builds, bundles, launches)
```

Open `Package.swift` in Xcode for SwiftUI previews. `rebuild.sh` wraps the binary in a signed (ad-hoc) `.app` bundle — a bundle is required for the drag-out to work.

To set an app icon, drop an `AppIcon.icns` in `Packaging/` and rebuild.

## How it works / caveats

- Glean reads **your own** Pinterest data via Pinterest's internal web endpoints (`BoardsResource`, `BoardFeedResource`) authenticated with your session cookies — not the official API. It's a personal, single-user tool.
- This is dependent on Pinterest's internal API, which can change without notice. The frontend build hash (`X-APP-VERSION`) is auto-detected from the homepage so it survives most deploys; larger changes may need a code update.
- Unsigned — see the Gatekeeper note above.

Geometry, motion, and the hotkey are all tweakable in `Sources/GleanKit/Window/IslandMetrics.swift` and `PanelController.swift`.
