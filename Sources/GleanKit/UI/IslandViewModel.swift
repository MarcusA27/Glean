import SwiftUI

@MainActor
public final class IslandViewModel: ObservableObject {
    @Published public var isExpanded = false
    @Published public var boards: [Board] = []
    @Published public var pins: [Pin] = []
    @Published public var selectedBoardID: String?
    /// Live search text. When non-empty, the grid filters across ALL pins (ignoring the
    /// selected board) by title match.
    @Published public var searchQuery = ""
    /// Pin id → its dominant color range (filled in lazily in the background).
    @Published public var pinColors: [String: ColorBucket] = [:]
    /// Pin id → Vision image-label tokens, so junk/empty-title pins are still searchable.
    @Published public var pinLabels: [String: [String]] = [:]
    /// The single color range the user is filtering by, if any.
    @Published public var selectedColor: ColorBucket?
    @Published public var isLoading = false
    @Published public var isReloading = false
    @Published public var confirmingLogout = false
    /// True while a pin is being dragged out; the window fades away during the drag.
    @Published public var isDragging = false
    /// Invoked when the stored session is rejected by the server (expired cookies).
    var onSessionExpired: (() -> Void)?
    /// Invoked when the user taps logout — clears the session and prompts a fresh login.
    var onLogoutRequested: (() -> Void)?
    /// Invoked when search opens/closes, so the panel can take/relinquish keyboard focus
    /// (it's otherwise non-key so it never steals focus).
    var onSearchModeChange: ((Bool) -> Void)?

    private var client: (any PinterestDataSource)?
    private var username: String?
    private var lastRefresh: Date?
    private var refreshing = false
    private var analyzing = false
    private let throttle: TimeInterval = 3 // re-check for new pins on (nearly) every open

    public var visiblePins: [Pin] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtering = !query.isEmpty || selectedColor != nil

        // Search and color filter both span every board; otherwise show the picked board.
        var result = filtering ? pins : (selectedBoardID.map { id in pins.filter { $0.boardID == id } } ?? pins)
        if !query.isEmpty {
            result = result.filter { pin in
                pin.title.lowercased().contains(query)
                    || (pinLabels[pin.id]?.contains { $0.contains(query) } ?? false)
            }
        }
        if let selectedColor {
            result = result.filter { (pinColors[$0.id] ?? .neutral) == selectedColor }
        }
        return result
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
    func connect(_ client: any PinterestDataSource) {
        self.client = client
        loadAnalysis()
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

        await client.prepare()

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
        boards = apiBoards

        var collected: [Pin] = []
        for board in apiBoards {
            var bookmark: String?
            var page = 0
            while page < 40 { // safety cap (~1000 pins/board)
                let (apiPins, next) = await client.fetchPins(
                    boardID: board.id, boardURL: board.url, bookmark: bookmark)
                collected.append(contentsOf: apiPins)
                if progressive { pins = collected }
                page += 1
                guard let next, next != "-end-" else { break }
                bookmark = next
            }
        }
        pins = collected
        analyzePins()
    }

    /// Cheap refresh: refetch boards + the first page of each, prepend pins we don't have.
    private func quickRefresh() async {
        guard let client, let user = username, !refreshing else { return }
        refreshing = true
        defer { refreshing = false; lastRefresh = Date() }

        let apiBoards = await client.fetchBoards(username: user)
        guard !apiBoards.isEmpty else { return } // likely a transient failure; leave pins as-is
        boards = apiBoards

        var firstPage: [Pin] = []
        for board in apiBoards {
            let (apiPins, _) = await client.fetchPins(boardID: board.id, boardURL: board.url, bookmark: nil)
            firstPage.append(contentsOf: apiPins)
        }

        let existing = Set(pins.map(\.id))
        let newOnes = firstPage.filter { !existing.contains($0.id) }
        if !newOnes.isEmpty {
            pins = newOnes + pins
            analyzePins()
        }
    }

    // MARK: - Color analysis (background, cached to disk)

    /// Classify the dominant color range of any pins we haven't seen yet, off the main
    /// thread, publishing in batches and persisting the result.
    private func analyzePins() {
        let todo = pins.filter { $0.thumbnailURL != nil && (pinColors[$0.id] == nil || pinLabels[$0.id] == nil) }
        guard !todo.isEmpty, !analyzing else { return }
        analyzing = true
        Task.detached(priority: .utility) { [weak self] in
            var colors: [String: ColorBucket] = [:]
            var labels: [String: [String]] = [:]
            for pin in todo {
                guard let url = pin.thumbnailURL,
                      let data = try? await URLSession.shared.data(from: url).0 else { continue }
                let bucket = ColorAnalyzer.bucket(forData: data)
                let tokens = LabelAnalyzer.labels(forData: data)
                guard bucket != nil || tokens != nil else { continue } // decode failed
                colors[pin.id] = bucket ?? .neutral
                labels[pin.id] = tokens ?? []
                if colors.count >= 16 {
                    let c = colors, l = labels
                    colors = [:]; labels = [:]
                    await self?.mergeAnalysis(colors: c, labels: l)
                }
            }
            await self?.mergeAnalysis(colors: colors, labels: labels)
            await self?.finishAnalysis()
        }
    }

    private func mergeAnalysis(colors: [String: ColorBucket], labels: [String: [String]]) {
        if !colors.isEmpty { pinColors.merge(colors) { _, fresh in fresh } }
        if !labels.isEmpty { pinLabels.merge(labels) { _, fresh in fresh } }
    }

    private func finishAnalysis() {
        analyzing = false
        persist(pinColors.mapValues { $0.rawValue }, to: "colors.json")
        persist(pinLabels, to: "labels.json")
    }

    private func analysisFileURL(_ name: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Glean", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func persist<T: Encodable>(_ value: T, to name: String) {
        guard let url = analysisFileURL(name) else { return }
        try? JSONEncoder().encode(value).write(to: url)
    }

    private func loadAnalysis() {
        if let url = analysisFileURL("colors.json"), let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            pinColors = raw.compactMapValues { ColorBucket(rawValue: $0) }
        }
        if let url = analysisFileURL("labels.json"), let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: [String]].self, from: data) {
            pinLabels = raw
        }
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
