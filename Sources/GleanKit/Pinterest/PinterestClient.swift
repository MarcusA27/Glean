import Foundation

/// Talks to Pinterest's internal endpoints using the captured session cookies.
@MainActor
final class PinterestClient {
    enum AuthResult { case ok(username: String?), unauthorized, networkError }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let cookies: [StoredCookie]
    private let session: URLSession
    /// Pinterest's frontend build hash. Refreshed from the homepage so internal calls
    /// keep working across their deploys; this baked-in value is just the fallback.
    private var appVersion = "1e6abbd"

    init(cookies: [StoredCookie]) {
        self.cookies = cookies
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil // we set the Cookie header explicitly
        session = URLSession(configuration: config)
    }

    /// Scrape the current build hash from the homepage HTML so requests aren't rejected
    /// after a Pinterest deploy. Leaves the fallback in place on failure.
    func refreshAppVersion() async {
        guard let url = URL(string: "https://www.pinterest.com/") else { return }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return }

        let pattern = #""app_version"\s*:\s*"([0-9a-f]{6,12})""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            appVersion = String(html[range])
        }
    }

    /// Distinguishes a live session from an expired one (vs a transient network error),
    /// so the app only re-prompts login when the session is actually invalid.
    func checkAuth() async -> AuthResult {
        let (status, body) = await getRaw(resource: "ApiResource",
                                          options: ["url": "/v3/users/me/", "data": ["fields": "username"]])
        switch status {
        case 200:
            struct Me: Decodable { let username: String? }
            let username = try? JSONDecoder()
                .decode(ResourceEnvelope<Me>.self, from: Data(body.utf8))
                .resourceResponse.data.username
            return .ok(username: username)
        case 401, 403:
            return .unauthorized
        default:
            return .networkError
        }
    }

    func fetchBoards(username: String) async -> [PinterestBoard] {
        let (status, body) = await getRaw(resource: "BoardsResource", options: [
            "page_size": 50,
            "privacy_filter": "all",
            "sort": "last_pinned_to",
            "username": username,
        ])
        guard status == 200, let data = body.data(using: .utf8),
              let env = try? JSONDecoder().decode(ResourceEnvelope<[PinterestBoard]>.self, from: data) else {
            return []
        }
        return env.resourceResponse.data
    }

    func fetchPins(boardID: String, boardURL: String, bookmark: String? = nil)
        async -> (pins: [PinterestPin], bookmark: String?) {
        var options: [String: Any] = [
            "board_id": boardID,
            "board_url": boardURL,
            "currentFilter": -1,
            "field_set_key": "react_grid_pin",
            "filter_section_pins": true,
            "sort": "default",
            "layout": "default",
            "page_size": 25,
            "redux_normalize_feed": true,
        ]
        if let bookmark { options["bookmarks"] = [bookmark] }

        let (status, body) = await getRaw(resource: "BoardFeedResource", options: options)
        guard status == 200, let data = body.data(using: .utf8),
              let env = try? JSONDecoder().decode(ResourceEnvelope<[Failable<PinterestPin>]>.self, from: data) else {
            return ([], nil)
        }
        let pins = env.resourceResponse.data.compactMap(\.value).filter { $0.thumbnailURL != nil }
        return (pins, env.resourceResponse.bookmark)
    }

    // MARK: - Raw

    private func getRaw(resource: String, options: [String: Any]) async -> (status: Int, body: String) {
        guard let url = Endpoints.url(resource: resource, options: options) else {
            return (-1, "")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (status, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }

    private func applyHeaders(to request: inout URLRequest) {
        let httpCookies = CookieStore.httpCookies(cookies)
        for (key, value) in HTTPCookie.requestHeaderFields(with: httpCookies) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json, text/javascript, */*, q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("https://www.pinterest.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.pinterest.com", forHTTPHeaderField: "Origin")
        request.setValue("active", forHTTPHeaderField: "X-Pinterest-AppState")
        request.setValue(appVersion, forHTTPHeaderField: "X-APP-VERSION")
        request.setValue("/", forHTTPHeaderField: "X-Pinterest-Source-Url")
        request.setValue("www/index.js", forHTTPHeaderField: "X-Pinterest-PWS-Handler")
        request.setValue("2", forHTTPHeaderField: "screen-dpr")
        if let csrf = CookieStore.csrfToken(cookies) {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        }
    }
}
