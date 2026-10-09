import Foundation

/// An OAuth token pair plus its access-token expiry.
struct OAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    /// Treat as expired a minute early so a request never fires on a just-dead token.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }

    init(accessToken: String, refreshToken: String?, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

/// Keychain-backed persistence for the OAuth token, mirroring `CookieStore` for the
/// cookie backend.
enum OAuthTokenStore {
    private static let service = "com.glean.pinterest.oauth"
    private static let account = "token"

    static func save(_ token: OAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        Keychain.set(data, service: service, account: account)
    }

    static func load() -> OAuthToken? {
        guard let data = Keychain.get(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    static func clear() {
        Keychain.delete(service: service, account: account)
    }
}
