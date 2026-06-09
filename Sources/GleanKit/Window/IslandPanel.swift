import AppKit

/// Borderless, non-activating floating panel. Never becomes key/main, so it never
/// steals focus from the app you're working in. Transparent; the SwiftUI content
/// draws the visible island.
final class IslandPanel: NSPanel {
    /// Allow keyboard focus only while the search field is active; otherwise the panel
    /// stays non-key so it never steals focus from the app you're working in.
    var keyboardEnabled = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        // Above the menu-bar window level so the island isn't clipped when it sits
        // high enough to overlap the menu-bar band.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        // Belongs to one Space (so it slides away naturally on a Space swipe instead of
        // staying frozen on top); summoning moves it to whatever Space is active.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // shadow is drawn by SwiftUI on the island shape
        isMovable = false                 // don't let window-drag compete with pin drag-out
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true     // needed for the local mouse-moved monitor
    }

    override var canBecomeKey: Bool { keyboardEnabled }
    override var canBecomeMain: Bool { false }

    // Don't let AppKit pull the panel back on-screen; the transparent shadow padding
    // is allowed to extend past the screen's top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
