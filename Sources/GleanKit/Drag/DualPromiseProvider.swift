import AppKit

/// An `NSFilePromiseProvider` that also advertises a concrete `file://` URL when one
/// is available (a prefetched temp file). Promise-aware targets (Finder, Figma) can
/// use either; URL-only targets (Electron apps, Terminal) use the file URL.
final class DualPromiseProvider: NSFilePromiseProvider {
    var fileURL: URL?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if fileURL != nil { types.append(.fileURL) }
        return types
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType,
                                 pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        // The file URL is available immediately; only the promise types are "promised".
        if type == .fileURL { return [] }
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL, let fileURL {
            return (fileURL as NSURL).pasteboardPropertyList(forType: .fileURL)
        }
        return super.pasteboardPropertyList(forType: type)
    }
}
