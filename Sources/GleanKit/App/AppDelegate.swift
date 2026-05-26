import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandViewModel()
    private var controller: PanelController?
    private let auth = PinterestAuth()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController(model: model)
        controller.show()
        self.controller = controller

        model.onSessionExpired = { [weak self] in self?.reauthenticate() }

        auth.loadSession { [weak self] cookies in
            self?.model.connect(PinterestClient(cookies: cookies))
        }
    }

    /// Stored cookies were rejected (expired). Clear them and prompt a fresh login.
    private func reauthenticate() {
        auth.relogin { [weak self] cookies in
            self?.model.connect(PinterestClient(cookies: cookies))
        }
    }
}
