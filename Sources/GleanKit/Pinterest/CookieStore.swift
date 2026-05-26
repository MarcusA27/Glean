import Foundation

struct StoredCookie: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
}

/// Persists the captured Pinterest session cookies in the Keychain and rebuilds
/// `HTTPCookie`s for use in `URLSession` requests to the internal endpoints.
enum CookieStore {
    private static let service = "com.marcusarocha.boardisland.cookies"
    private static let account = "pinterest"

    static func save(_ cookies: [StoredCookie]) {
        guard let data = try? JSONEncoder().encode(cookies) else { return }
        Keychain.set(data, service: service, account: account)
    }

    static func load() -> [StoredCookie] {
        guard let data = Keychain.get(service: service, account: account),
              let cookies = try? JSONDecoder().decode([StoredCookie].self, from: data) else {
            return []
        }
        return cookies
    }

    static func clear() {
        Keychain.delete(service: service, account: account)
    }

    static func httpCookies(_ stored: [StoredCookie]) -> [HTTPCookie] {
        stored.compactMap { cookie in
            HTTPCookie(properties: [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
            ])
        }
    }

    static func csrfToken(_ stored: [StoredCookie]) -> String? {
        stored.first { $0.name == "csrftoken" }?.value
    }
}
