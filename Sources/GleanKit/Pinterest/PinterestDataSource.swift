import Foundation

/// Outcome of a session check, shared by both the cookie and OAuth backends.
enum PinterestAuthResult {
    case ok(username: String?)
    case unauthorized
    case networkError
}

/// A source of the user's boards and pins. Two backends implement this: the legacy
/// cookie-scraping `PinterestClient` (internal `/resource/` endpoints) and the
/// `OfficialPinterestClient` (OAuth2 v5 API). The view model talks only to this.
@MainActor
protocol PinterestDataSource: AnyObject {
    /// Backend-specific warm-up before a load (refresh a build hash / an access token).
    func prepare() async
    /// Distinguish a live session from an expired one vs a transient network error.
    func checkAuth() async -> PinterestAuthResult
    /// All of the user's boards. `username` is used by the cookie backend; the OAuth
    /// backend is scoped to the token's account and ignores it.
    func fetchBoards(username: String) async -> [Board]
    /// One page of a board's pins plus the cursor for the next page (nil when done).
    func fetchPins(boardID: String, boardURL: String, bookmark: String?)
        async -> (pins: [Pin], bookmark: String?)
}
