import AppKit
import WebKit

/// Bare token-exchange calls against `POST /v5/oauth/token` (HTTP Basic with the app's
/// client id/secret, form-encoded body). Used by both the login flow and the client's
/// silent refresh.
enum PinterestOAuthAPI {
    static let tokenURL = URL(string: "https://api.pinterest.com/v5/oauth/token")!

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    static func exchange(code: String, creds: OAuthCredentials) async -> OAuthToken? {
        await post(body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": creds.redirectURI,
            "continuous_refresh": "true",
        ], creds: creds, previousRefresh: nil)
    }

    static func refresh(refreshToken: String, creds: OAuthCredentials) async -> OAuthToken? {
        await post(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "continuous_refresh": "true",
        ], creds: creds, previousRefresh: refreshToken)
    }

    private static func post(body: [String: String], creds: OAuthCredentials,
                             previousRefresh: String?) async -> OAuthToken? {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let creds64 = Data("\(creds.clientID):\(creds.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(creds64)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            return nil
        }
        // Continuous-refresh may or may not reissue the refresh token; keep the old one if not.
        return OAuthToken(accessToken: decoded.access_token,
                          refreshToken: decoded.refresh_token ?? previousRefresh,
                          expiresIn: decoded.expires_in)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// First-run OAuth login for the official API: loads Pinterest's authorize page in a
/// WKWebView, intercepts the redirect back to the app's `redirect_uri`, and exchanges the
/// returned `code` for a token. Mirrors `PinterestAuth`'s window handling.
@MainActor
final class PinterestOAuth: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var creds: OAuthCredentials?
    private var state = ""
    private var onComplete: ((OAuthToken) -> Void)?
    private var finished = false

    /// Reuse a stored token (refreshing if stale) or present the login page.
    func loadSession(credentials: OAuthCredentials, completion: @escaping (OAuthToken) -> Void) {
        creds = credentials
        onComplete = completion

        if let existing = OAuthTokenStore.load() {
            if !existing.isExpired {
                deliver(existing)
                return
            }
            if let refresh = existing.refreshToken {
                Task { [weak self] in
                    if let renewed = await PinterestOAuthAPI.refresh(refreshToken: refresh, creds: credentials) {
                        OAuthTokenStore.save(renewed)
                        self?.deliver(renewed)
                    } else {
                        self?.presentLogin()
                    }
                }
                return
            }
        }
        presentLogin()
    }

    /// Force a fresh grant after the token is rejected: drop the stored token and log in.
    func relogin(credentials: OAuthCredentials, completion: @escaping (OAuthToken) -> Void) {
        creds = credentials
        onComplete = completion
        finished = false
        OAuthTokenStore.clear()
        presentLogin()
    }

    private func authorizeURL(_ creds: OAuthCredentials) -> URL? {
        var comps = URLComponents(string: "https://www.pinterest.com/oauth/")
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: creds.clientID),
            URLQueryItem(name: "redirect_uri", value: creds.redirectURI),
            URLQueryItem(name: "scope", value: OAuthCredentials.scope),
            URLQueryItem(name: "state", value: state),
        ]
        return comps?.url
    }

    private func presentLogin() {
        guard let creds else { return }
        state = UUID().uuidString
        guard let url = authorizeURL(creds) else { return }

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 720))
        web.customUserAgent = PinterestClient.userAgent
        web.navigationDelegate = self
        webView = web

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Authorize Glean"
        win.contentView = web
        win.center()
        win.isReleasedWhenClosed = false
        window = win

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        web.load(URLRequest(url: url))
    }

    /// True when a URL is the registered redirect target (ignoring the query string).
    private func isRedirect(_ url: URL, _ creds: OAuthCredentials) -> Bool {
        guard let redirect = URLComponents(string: creds.redirectURI),
              let incoming = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return incoming.scheme == redirect.scheme
            && incoming.host == redirect.host
            && incoming.path == redirect.path
    }

    private func handleCode(_ code: String) {
        guard let creds, !finished else { return }
        finished = true
        Task { [weak self] in
            guard let token = await PinterestOAuthAPI.exchange(code: code, creds: creds) else {
                self?.finished = false
                return
            }
            OAuthTokenStore.save(token)
            self?.closeWindow()
            self?.deliver(token)
        }
    }

    private func closeWindow() {
        window?.close()
        window = nil
        webView = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func deliver(_ token: OAuthToken) {
        let callback = onComplete
        onComplete = nil
        callback?(token)
    }
}

extension PinterestOAuth: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let creds, let url = navigationAction.request.url, isRedirect(url, creds) else {
            decisionHandler(.allow)
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let returnedState = items?.first { $0.name == "state" }?.value
        if let code = items?.first(where: { $0.name == "code" })?.value, returnedState == state {
            handleCode(code)
        }
        decisionHandler(.cancel)
    }
}
