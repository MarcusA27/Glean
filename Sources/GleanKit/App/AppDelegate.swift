import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Flip to the official OAuth v5 API instead of the cookie backend. Off by default so
    /// the proven cookie path stays in place until the OAuth path is verified end-to-end.
    static let useOfficialAPIKey = "GleanUseOfficialAPI"

    private let model = IslandViewModel()
    private var controller: PanelController?
    private let auth = PinterestAuth()
    private let oauth = PinterestOAuth()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController(model: model)
        controller.onToggleOfficialAPI = { [weak self] in self?.toggleOfficialAPI() }
        controller.show()
        self.controller = controller

        model.onSessionExpired = { [weak self] in self?.reauthenticate() }
        model.onLogoutRequested = { [weak self] in self?.reauthenticate() }

        connect()
    }

    /// True when the official API is both requested and configured with credentials.
    private var officialCredentials: OAuthCredentials? {
        guard UserDefaults.standard.bool(forKey: Self.useOfficialAPIKey) else { return nil }
        return OAuthCredentials.load()
    }

    /// Load a session via whichever backend is selected and hand the client to the model.
    private func connect() {
        if let creds = officialCredentials {
            oauth.loadSession(credentials: creds) { [weak self] token in
                self?.model.connect(OfficialPinterestClient(credentials: creds, token: token))
            }
        } else {
            auth.loadSession { [weak self] cookies in
                self?.model.connect(PinterestClient(cookies: cookies))
            }
        }
    }

    /// The stored session was rejected (expired). Clear it and prompt a fresh login on the
    /// selected backend.
    private func reauthenticate() {
        if let creds = officialCredentials {
            oauth.relogin(credentials: creds) { [weak self] token in
                self?.model.connect(OfficialPinterestClient(credentials: creds, token: token))
            }
        } else {
            auth.relogin { [weak self] cookies in
                self?.model.connect(PinterestClient(cookies: cookies))
            }
        }
    }

    /// Menu action: switch backends and reconnect. Reuses the logout reset so the grid
    /// clears before the new backend loads.
    private func toggleOfficialAPI() {
        let defaults = UserDefaults.standard
        let turningOn = !defaults.bool(forKey: Self.useOfficialAPIKey)
        if turningOn && OAuthCredentials.load() == nil {
            presentMissingCredentialsAlert()
            return
        }
        defaults.set(turningOn, forKey: Self.useOfficialAPIKey)
        connect()
    }

    private func presentMissingCredentialsAlert() {
        let alert = NSAlert()
        alert.messageText = "Pinterest API not configured"
        alert.informativeText = "Add your client_id, client_secret, and redirect_uri to "
            + (OAuthCredentials.configURL()?.path ?? "the Glean support directory")
            + " and try again."
        alert.runModal()
    }
}
