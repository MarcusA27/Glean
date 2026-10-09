import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
public final class PanelController: NSObject {
    private let panel: IslandPanel
    private let model: IslandViewModel
    private var hoverMonitor: HoverMonitor?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    /// Invoked when the user toggles the official-API menu item, so the app can switch
    /// backends and reconnect.
    var onToggleOfficialAPI: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var wasDragging = false
    /// Blocked leftward motion accumulated while the cursor is pinned at the left edge.
    private var pushAccum: CGFloat = 0
    /// Event timestamp at which the cursor first touched the wall this contact.
    private var wallContactTime: TimeInterval?

    public init(model: IslandViewModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: DrawerMetrics.windowSize))
        super.init()

        let host = NSHostingView(rootView: DrawerView(model: model))
        host.frame = NSRect(origin: .zero, size: DrawerMetrics.windowSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.ignoresMouseEvents = true // pass-through to other apps until summoned
    }

    public func show() {
        reposition()
        panel.orderFrontRegardless()
        setupStatusItem()

        let monitor = HoverMonitor { [weak self] location, deltaX, _, timestamp in
            self?.handleMouse(at: location, deltaX: deltaX, timestamp: timestamp)
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

        // Hide on a Space switch (4-finger swipe) so it doesn't reappear abruptly.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }

        // ⌥⌘B toggles the window open/closed, system-wide.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_B),
                        modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggle()
        }

        // Search needs keyboard focus, which the panel otherwise refuses. Grant it only
        // while searching, then drop the field's focus when search closes.
        model.onSearchModeChange = { [weak self] active in
            guard let self else { return }
            self.panel.keyboardEnabled = active
            if active {
                self.panel.makeKeyAndOrderFront(nil)
            } else {
                self.panel.makeFirstResponder(nil)
            }
        }

        // While a pin drags out, let the (faded) panel pass mouse events through so the
        // drop lands on the app underneath; once the drag ends, stay hidden.
        model.$isDragging
            .sink { [weak self] dragging in
                guard let self else { return }
                if dragging {
                    self.wasDragging = true
                    self.panel.ignoresMouseEvents = true
                } else if self.wasDragging {
                    self.wasDragging = false
                    self.close()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Open / close

    private func open() {
        pushAccum = 0
        wallContactTime = nil
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless() // bring it onto the current Space
        model.isExpanded = true
        model.refreshIfStale()
    }

    private func close() {
        pushAccum = 0
        wallContactTime = nil
        model.isExpanded = false
        model.confirmingLogout = false
        panel.ignoresMouseEvents = true
    }

    public func toggle() {
        if model.isExpanded { close() } else { open() }
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            item.button?.image = Self.menuBarIcon(from: image)
        } else {
            item.button?.title = "Glean"
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Show / Hide", action: #selector(menuToggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let refresh = NSMenuItem(title: "Refresh Pins", action: #selector(menuRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let official = NSMenuItem(title: "Use Official API (beta)", action: #selector(menuToggleOfficialAPI), keyEquivalent: "")
        official.target = self
        official.state = UserDefaults.standard.bool(forKey: AppDelegate.useOfficialAPIKey) ? .on : .off
        menu.addItem(official)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Glean", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuRefresh() { model.reload() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuToggleOfficialAPI(_ sender: NSMenuItem) {
        onToggleOfficialAPI?()
        sender.state = UserDefaults.standard.bool(forKey: AppDelegate.useOfficialAPIKey) ? .on : .off
    }

    private static func menuBarIcon(from source: NSImage, size: CGFloat = 18, radius: CGFloat = 4.5) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        NSColor(white: 0.11, alpha: 1.0).setFill()
        rect.fill()
        source.draw(in: rect.insetBy(dx: 1, dy: 1), from: .zero, operation: .sourceOver, fraction: 1.0)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Positioning

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame // full screen, so it's centered between the actual edges
        let size = DrawerMetrics.windowSize
        panel.setFrame(NSRect(x: f.midX - size.width / 2,
                              y: f.midY - size.height / 2,
                              width: size.width, height: size.height),
                       display: true)
    }

    // MARK: - Edge-push summon

    private func handleMouse(at location: CGPoint, deltaX: CGFloat, timestamp: TimeInterval) {
        guard !model.isExpanded else { return } // stays open until toggled off
        panel.ignoresMouseEvents = true

        guard let screen = NSScreen.main else { return }
        let edge = screen.frame.minX
        guard location.x <= edge + DrawerMetrics.edgeBand else {
            wallContactTime = nil
            pushAccum = 0
            return
        }
        guard let contact = wallContactTime else {
            wallContactTime = timestamp
            pushAccum = 0
            return
        }
        // Discard the arrival fling; only count a push that continues past the window.
        guard timestamp - contact >= DrawerMetrics.momentumWindow else { return }
        if deltaX < 0 {
            pushAccum += -deltaX
            if pushAccum >= DrawerMetrics.pushThreshold { open() }
        } else if deltaX > 0 {
            pushAccum = 0
        }
    }
}
