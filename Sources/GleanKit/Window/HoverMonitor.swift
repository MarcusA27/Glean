import AppKit

/// Reports cursor movement in screen coordinates. We use raw event monitors rather
/// than SwiftUI `.onHover`/`NSTrackingArea`, because the app is `.accessory` and never
/// becomes active — tracking-area hover doesn't fire reliably for an inactive app.
///
/// - The global monitor fires while the cursor is over *other* apps (i.e. while the
///   panel ignores mouse events), so it detects the cursor entering the pill.
/// - The local monitor fires while the cursor is over our panel (mouse events enabled).
@MainActor
final class HoverMonitor {
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    /// Reports the absolute cursor location, the event's horizontal/vertical deltas,
    /// and its timestamp. The deltas keep reporting device motion even when the cursor
    /// is clamped at a screen edge — that's how an intentional "shove into the wall" is
    /// detected, on whichever edge the drawer is docked; the timestamp lets us discard
    /// the arrival momentum first.
    private let onMove: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void

    init(onMove: @escaping (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void) {
        self.onMove = onMove
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.onMove(NSEvent.mouseLocation, event.deltaX, event.deltaY, event.timestamp)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.onMove(NSEvent.mouseLocation, event.deltaX, event.deltaY, event.timestamp)
            }
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
