import AppKit

/// Prefetches a pin's full-res `orig` to a temp file when you hover it, so a drag
/// can hand over a concrete `file://` URL (needed by Electron/web apps like the
/// Claude desktop app and by Terminal, which ignore file promises).
@MainActor
enum FullResCache {
    private static var files: [String: URL] = [:]
    private static var inFlight: Set<String> = []

    static func cached(_ pinID: String) -> URL? { files[pinID] }

    static func prefetch(pinID: String, remoteURL: URL) {
        guard files[pinID] == nil, !inFlight.contains(pinID) else { return }
        inFlight.insert(pinID)
        Task { @MainActor in
            defer { inFlight.remove(pinID) }
            guard let (data, _) = try? await URLSession.shared.data(from: remoteURL) else { return }
            let ext = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pin-\(pinID).\(ext)")
            if (try? data.write(to: url)) != nil {
                files[pinID] = url
            }
        }
    }
}
