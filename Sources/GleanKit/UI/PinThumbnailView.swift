import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ThumbnailLoader {
    // NSCache is internally thread-safe; the unsafe marker just satisfies Swift 6's
    // global-variable concurrency check.
    nonisolated(unsafe) static let cache = NSCache<NSURL, NSImage>()

    static func fetchData(_ url: URL) async -> Data? {
        (try? await URLSession.shared.data(from: url))?.0
    }
}

/// A pin tile: an AppKit view so it can be a file-promise drag source (SwiftUI
/// `.onDrag` doesn't compose with promises). Draws the cached 236x thumbnail and,
/// on drag, vends the pin's full-res via a lazy promise. `onDragStateChange` lets
/// the panel keep the island open during a drag.
final class PinTileNSView: NSView, NSDraggingSource {
    private var pin: Pin
    private let onDragStateChange: (Bool) -> Void
    private var thumbnail: NSImage?
    private var promiseDelegate: PinFilePromiseDelegate?

    init(pin: Pin, onDragStateChange: @escaping (Bool) -> Void) {
        self.pin = pin
        self.onDragStateChange = onDragStateChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.contentsGravity = .resizeAspectFill
        loadThumbnail()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(pin: Pin) {
        guard pin.id != self.pin.id else { return }
        self.pin = pin
        thumbnail = nil
        layer?.contents = nil
        loadThumbnail()
    }

    // Allow a drag to begin without first activating the (non-activating) panel.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    // Prefetch the full-res as soon as the cursor reaches the tile (and again on press),
    // so it's on disk by the time a drag begins and we can vend a real file URL — which
    // Electron/web targets (Claude desktop) need.
    override func mouseEntered(with event: NSEvent) {
        prefetchFullRes()
    }

    override func mouseDown(with event: NSEvent) {
        prefetchFullRes()
        super.mouseDown(with: event)
    }

    private func prefetchFullRes() {
        guard let url = pin.fullResURL else { return }
        FullResCache.prefetch(pinID: pin.id, remoteURL: url)
    }

    private func loadThumbnail() {
        guard let url = pin.thumbnailURL else { return }
        if let cached = ThumbnailLoader.cache.object(forKey: url as NSURL) {
            apply(cached)
            return
        }
        let pinID = pin.id
        Task { @MainActor in
            guard let data = await ThumbnailLoader.fetchData(url), let image = NSImage(data: data) else { return }
            ThumbnailLoader.cache.setObject(image, forKey: url as NSURL)
            guard self.pin.id == pinID else { return } // tile may have been reused while loading
            self.apply(image)
        }
    }

    private func apply(_ image: NSImage) {
        thumbnail = image
        layer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fullRes = pin.fullResURL else { return }
        let ext = fullRes.pathExtension.isEmpty ? "jpg" : fullRes.pathExtension
        let type = UTType(filenameExtension: ext) ?? .jpeg
        let local = FullResCache.cached(pin.id)

        let delegate = PinFilePromiseDelegate(remoteURL: fullRes, localURL: local,
                                              filename: "pin-\(pin.id).\(ext)")
        promiseDelegate = delegate // NSFilePromiseProvider holds its delegate weakly

        // If the full-res is already on disk, also vend a concrete file URL so
        // Electron/web apps (Claude desktop) and Terminal accept the drop.
        let provider: NSFilePromiseProvider
        if let local {
            let dual = DualPromiseProvider(fileType: type.identifier, delegate: delegate)
            dual.fileURL = local
            provider = dual
        } else {
            provider = NSFilePromiseProvider(fileType: type.identifier, delegate: delegate)
        }

        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: thumbnail)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragStateChange(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onDragStateChange(false)
    }
}

struct PinThumbnailView: NSViewRepresentable {
    let pin: Pin
    let onDragStateChange: (Bool) -> Void

    func makeNSView(context: Context) -> PinTileNSView {
        PinTileNSView(pin: pin, onDragStateChange: onDragStateChange)
    }

    func updateNSView(_ nsView: PinTileNSView, context: Context) {
        nsView.update(pin: pin)
    }
}
