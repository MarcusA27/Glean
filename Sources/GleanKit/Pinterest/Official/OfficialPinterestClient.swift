import Foundation

/// Reads the user's boards and pins via Pinterest's official OAuth2 v5 API.
/// Full-res drag URLs come from the `originals/` CDN rewrite in `V5Pin` (the v5 API
/// itself caps images at 1200px). Silently refreshes the access token on 401.
@MainActor
final class OfficialPinterestClient: PinterestDataSource {
    private static let base = URL(string: "https://api.pinterest.com/v5")!

    private let creds: OAuthCredentials
    private var token: OAuthToken

    init(credentials: OAuthCredentials, token: OAuthToken) {
        self.creds = credentials
        self.token = token
    }

    /// Refresh the access token ahead of a load if it's expired.
    func prepare() async {
        guard token.isExpired, let refresh = token.refreshToken,
              let renewed = await PinterestOAuthAPI.refresh(refreshToken: refresh, creds: creds) else { return }
        token = renewed
        OAuthTokenStore.save(renewed)
    }

    func checkAuth() async -> PinterestAuthResult {
        let (status, data) = await get(path: "/user_account", query: [])
        switch status {
        case 200:
            let username = data.flatMap { try? JSONDecoder().decode(V5UserAccount.self, from: $0) }?.username
            return .ok(username: username)
        case 401, 403:
            return .unauthorized
        default:
            return .networkError
        }
    }

    func fetchBoards(username: String) async -> [Board] {
        var collected: [Board] = []
        var bookmark: String?
        var page = 0
        repeat {
            var query = [URLQueryItem(name: "page_size", value: "100")]
            if let bookmark { query.append(URLQueryItem(name: "bookmark", value: bookmark)) }
            let (status, data) = await get(path: "/boards", query: query)
            guard status == 200, let data,
                  let env = try? JSONDecoder().decode(V5Page<V5Board>.self, from: data) else { break }
            collected.append(contentsOf: env.items.map {
                Board(id: $0.id, name: $0.name ?? "Untitled", url: "")
            })
            bookmark = env.bookmark
            page += 1
        } while bookmark != nil && page < 20
        return collected
    }

    func fetchPins(boardID: String, boardURL: String, bookmark: String?)
        async -> (pins: [Pin], bookmark: String?) {
        var query = [URLQueryItem(name: "page_size", value: "100")]
        if let bookmark { query.append(URLQueryItem(name: "bookmark", value: bookmark)) }
        let (status, data) = await get(path: "/boards/\(boardID)/pins", query: query)
        guard status == 200, let data,
              let env = try? JSONDecoder().decode(V5Page<V5Pin>.self, from: data) else {
            return ([], nil)
        }
        let pins = env.items
            .filter { $0.thumbnailURL != nil }
            .map { pin in
                Pin(id: pin.id,
                    boardID: boardID,
                    title: pin.title_,
                    thumbnailURL: pin.thumbnailURL.flatMap(URL.init(string:)),
                    fullResURL: pin.fullResURL.flatMap(URL.init(string:)))
            }
        return (pins, env.bookmark)
    }

    // MARK: - Raw

    /// GET with the bearer token. On 401, refresh once and retry so a token that expired
    /// mid-session recovers without bouncing the user to re-auth.
    private func get(path: String, query: [URLQueryItem]) async -> (status: Int, data: Data?) {
        let result = await send(path: path, query: query)
        guard result.status == 401, let refresh = token.refreshToken,
              let renewed = await PinterestOAuthAPI.refresh(refreshToken: refresh, creds: creds) else {
            return result
        }
        token = renewed
        OAuthTokenStore.save(renewed)
        return await send(path: path, query: query)
    }

    private func send(path: String, query: [URLQueryItem]) async -> (status: Int, data: Data?) {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query.isEmpty ? nil : query
        guard let url = comps?.url else { return (-1, nil) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
        } catch {
            return (-1, nil)
        }
    }
}
