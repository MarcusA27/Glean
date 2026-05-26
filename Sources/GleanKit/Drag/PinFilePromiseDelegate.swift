import AppKit

/// Vends a pin's full-res image only when the drop target asks for it: the `orig`
/// URL is downloaded on the work queue straight into the destination the receiver
/// chose. Lazy — nothing downloads unless you actually drop.
///
/// Methods are `nonisolated` on purpose: AppKit's file-provider XPC calls them off
/// the main thread despite their `NS_SWIFT_UI_ACTOR` annotation (see memory/dragout-findings).
final class PinFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let localURL: URL?
    private let filename: String
    private let workQueue: OperationQueue

    init(remoteURL: URL, localURL: URL?, filename: String) {
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.filename = filename
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        self.workQueue = queue
        super.init()
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider,
                                         fileNameForType fileType: String) -> String {
        filename
    }

    nonisolated func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        workQueue
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider,
                                         writePromiseTo url: URL,
                                         completionHandler: @escaping (Error?) -> Void) {
        do {
            if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.copyItem(at: localURL, to: url) // prefetched
            } else {
                let data = try Data(contentsOf: remoteURL) // downloads on workQueue
                try data.write(to: url)
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
