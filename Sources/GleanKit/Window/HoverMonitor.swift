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
    private let onMove: (CGPoint) -> Void

    init(onMove: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onMove(NSEvent.mouseLocation)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.onMove(NSEvent.mouseLocation)
            }
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
