import Foundation

/// App credentials for the official v5 API. Read at runtime from
/// `~/Library/Application Support/Glean/oauth.json` so the client secret never lives in
/// git or the binary. Expected shape:
///
///     { "client_id": "1579304",
///       "client_secret": "…",
///       "redirect_uri": "https://localhost/glean/callback" }
///
/// `redirect_uri` must exactly match one registered on the Pinterest app.
struct OAuthCredentials {
    let clientID: String
    let clientSecret: String
    let redirectURI: String

    /// Scopes the app needs: read the user's boards, pins, and account (for the username).
    static let scope = "boards:read,pins:read,user_accounts:read"

    static func configURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Glean/oauth.json")
    }

    static func load() -> OAuthCredentials? {
        guard let url = configURL(), let data = try? Data(contentsOf: url) else { return nil }
        struct Raw: Decodable {
            let client_id: String
            let client_secret: String
            let redirect_uri: String
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data),
              !raw.client_id.isEmpty, !raw.client_secret.isEmpty, !raw.redirect_uri.isEmpty else {
            return nil
        }
        return OAuthCredentials(clientID: raw.client_id,
                                clientSecret: raw.client_secret,
                                redirectURI: raw.redirect_uri)
    }
}
