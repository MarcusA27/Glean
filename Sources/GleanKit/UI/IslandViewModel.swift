import SwiftUI

@MainActor
public final class IslandViewModel: ObservableObject {
    @Published public var isExpanded = false
    @Published public var boards: [Board] = []
    @Published public var pins: [Pin] = []
    @Published public var selectedBoardID: String?
    @Published public var isLoading = false
    @Published public var isReloading = false
    @Published public var confirmingLogout = false
    /// True while a pin is being dragged out; keeps the island from collapsing mid-drag.
    public var isDragging = false
    /// Invoked when the stored session is rejected by the server (expired cookies).
    var onSessionExpired: (() -> Void)?
    /// Invoked when the user taps logout — clears the session and prompts a fresh login.
    var onLogoutRequested: (() -> Void)?

    private var client: PinterestClient?
    private var username: String?
    private var lastRefresh: Date?
    private var refreshing = false
    private let throttle: TimeInterval = 3 // re-check for new pins on (nearly) every open

    public var visiblePins: [Pin] {
        guard let selectedBoardID else { return pins }
        return pins.filter { $0.boardID == selectedBoardID }
    }

    public init() {}

    /// User-initiated logout: clear shown content and ask to re-authenticate.
    public func requestLogout() {
        pins = []
        boards = []
        selectedBoardID = nil
        username = nil
        lastRefresh = nil
        onLogoutRequested?()
    }

    /// Called once at launch (and after re-auth): store the session client and load.
    func connect(_ client: PinterestClient) {
        self.client = client
        Task { await fullLoad(progressive: true) }
    }

    /// Called when the island opens. Cheaply checks for new pins if it's been a few seconds.
    func refreshIfStale() {
        guard let lastRefresh, !refreshing,
              Date().timeIntervalSince(lastRefresh) > throttle else { return }
        Task { await quickRefresh() }
    }

    /// Manual full refresh — re-fetches everything so moved pins, new boards, and
    /// re-orderings are all reflected. Keeps current tiles until the new set is ready.
    public func reload() {
        guard !refreshing else { return }
        Task { @MainActor in
            isReloading = true
            await fullLoad(progressive: false)
            isReloading = false
        }
    }

    /// Full paginated load. `progressive` streams tiles in as pages arrive (first load);
    /// otherwise existing tiles stay put and the fresh set swaps in at the end.
    private func fullLoad(progressive: Bool) async {
        guard let client, !refreshing else { return }
        refreshing = true
        if progressive { isLoading = pins.isEmpty }
        defer { refreshing = false; isLoading = false; lastRefresh = Date() }

        await client.refreshAppVersion()

        switch await client.checkAuth() {
        case .ok(let user):
            username = user ?? username ?? "marcusraarocha"
        case .unauthorized:
            onSessionExpired?()
            return
        case .networkError:
            return // keep whatever we have; try again on next open
        }
        guard let user = username else { return }

        let apiBoards = await client.fetchBoards(username: user)
        boards = apiBoards.map { Board(id: $0.id, name: $0.name, url: $0.url) }

        var collected: [Pin] = []
        for board in apiBoards {
            var bookmark: String?
            var page = 0
            while page < 40 { // safety cap (~1000 pins/board)
                let (apiPins, next) = await client.fetchPins(
                    boardID: board.id, boardURL: board.url, bookmark: bookmark)
                collected.append(contentsOf: apiPins.map { mapPin($0, boardID: board.id) })
                if progressive { pins = collected }
                page += 1
                guard let next, next != "-end-" else { break }
                bookmark = next
            }
        }
        pins = collected
    }

    /// Cheap refresh: refetch boards + the first page of each, prepend pins we don't have.
    private func quickRefresh() async {
        guard let client, let user = username, !refreshing else { return }
        refreshing = true
        defer { refreshing = false; lastRefresh = Date() }

        let apiBoards = await client.fetchBoards(username: user)
        guard !apiBoards.isEmpty else { return } // likely a transient failure; leave pins as-is
        boards = apiBoards.map { Board(id: $0.id, name: $0.name, url: $0.url) }

        var firstPage: [Pin] = []
        for board in apiBoards {
            let (apiPins, _) = await client.fetchPins(boardID: board.id, boardURL: board.url)
            firstPage.append(contentsOf: apiPins.map { mapPin($0, boardID: board.id) })
        }

        let existing = Set(pins.map(\.id))
        let newOnes = firstPage.filter { !existing.contains($0.id) }
        if !newOnes.isEmpty {
            pins = newOnes + pins
        }
    }

    private func mapPin(_ pin: PinterestPin, boardID: String) -> Pin {
        Pin(id: pin.id,
            boardID: boardID,
            title: pin.title,
            thumbnailURL: pin.thumbnailURL.flatMap(URL.init(string:)),
            fullResURL: pin.fullResURL.flatMap(URL.init(string:)))
    }

    /// Placeholder content for SwiftUI previews (no network).
    static func sample() -> IslandViewModel {
        let model = IslandViewModel()
        model.boards = [
            Board(id: "b1", name: "style", url: "/me/style/"),
            Board(id: "b2", name: "interiors", url: "/me/interiors/"),
        ]
        model.pins = (0..<10).map {
            Pin(id: "p\($0)", boardID: $0 % 2 == 0 ? "b1" : "b2",
                title: "Sample pin \($0)", thumbnailURL: nil, fullResURL: nil)
        }
        return model
    }
}
