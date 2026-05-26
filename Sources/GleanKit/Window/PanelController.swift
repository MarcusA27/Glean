import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
public final class PanelController {
    private let panel: IslandPanel
    private let model: IslandViewModel
    private var hoverMonitor: HoverMonitor?
    private var collapseTask: Task<Void, Never>?
    private var hotKey: HotKey?
    private var isHidden = false

    public init(model: IslandViewModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandMetrics.panelSize))

        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = NSRect(origin: .zero, size: IslandMetrics.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.ignoresMouseEvents = true // pass-through until the cursor reaches the pill
    }

    public func show() {
        reposition()
        panel.orderFrontRegardless()

        let monitor = HoverMonitor { [weak self] location in
            self?.handleMouse(at: location)
        }
        monitor.start()
        hoverMonitor = monitor

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        // ⌥⌘B toggles the island hidden/shown, system-wide.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_B),
                        modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleHidden()
        }
    }

    public func toggleHidden() {
        isHidden.toggle()
        if isHidden {
            model.isExpanded = false
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        } else {
            reposition()
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Positioning

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = IslandMetrics.panelSize
        // Anchor the island's top edge just below the menu bar; the panel extends
        // shadowPadding above that and the full expanded height (plus padding) below.
        let islandTopY = vf.maxY + IslandMetrics.topOffset
        let originY = islandTopY - IslandMetrics.expanded.height - IslandMetrics.shadowPadding
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: originY,
                              width: size.width, height: size.height),
                       display: true)
    }

    /// The visible island's rect in screen coordinates for a given size (top-anchored, centered).
    private func islandScreenRect(for size: CGSize) -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        let vf = screen.visibleFrame
        let islandTopY = vf.maxY + IslandMetrics.topOffset
        return CGRect(x: vf.midX - size.width / 2,
                      y: islandTopY - size.height,
                      width: size.width, height: size.height)
    }

    // MARK: - Hover state machine

    private func handleMouse(at location: CGPoint) {
        guard !isHidden else { return }
        let slop = IslandMetrics.hoverSlop
        if model.isExpanded {
            // Never collapse mid-drag, even as the cursor leaves the island.
            if model.isDragging {
                cancelCollapse()
                panel.ignoresMouseEvents = false
                return
            }
            let rect = islandScreenRect(for: IslandMetrics.expanded).insetBy(dx: -slop, dy: -slop)
            if rect.contains(location) {
                cancelCollapse()
                panel.ignoresMouseEvents = false
            } else {
                scheduleCollapse()
            }
        } else {
            let rect = islandScreenRect(for: IslandMetrics.collapsed).insetBy(dx: -slop, dy: -slop)
            if rect.contains(location) {
                panel.ignoresMouseEvents = false
                if !model.isExpanded {
                    model.isExpanded = true
                    model.refreshIfStale() // pick up newly added pins when opened
                }
            } else {
                panel.ignoresMouseEvents = true
            }
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return } // schedule once on inside->outside
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: IslandMetrics.collapseDelay)
            guard let self, !Task.isCancelled else { return }
            self.collapseTask = nil
            self.model.isExpanded = false
            self.panel.ignoresMouseEvents = true
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }
}
