import Foundation

/// v5 list envelope: `{"items": [...], "bookmark": "..."}`.
struct V5Page<T: Decodable>: Decodable {
    let items: [T]
    let bookmark: String?
}

struct V5Board: Decodable {
    let id: String
    let name: String?
}

struct V5UserAccount: Decodable {
    let username: String?
}

/// A v5 image bucket (`150x150`, `400x300`, `600x`, `1200x`).
struct V5Image: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

/// `media` is a discriminated union; only image pins carry an `images` map. Video/story
/// pins decode to `images == nil` and are dropped (they have no draggable still).
struct V5Media: Decodable {
    let images: [String: V5Image]?
}

struct V5Pin: Decodable {
    let id: String
    let title: String?
    let altText: String?
    let description: String?
    let boardID: String?
    let media: V5Media?

    enum CodingKeys: String, CodingKey {
        case id, title, description, media
        case altText = "alt_text"
        case boardID = "board_id"
    }

    /// Largest bucket the API returns (capped at 1200px wide).
    private var largest: V5Image? {
        media?.images.flatMap { imgs in
            ["1200x", "600x", "400x300", "150x150"].lazy.compactMap { imgs[$0] }.first
        }
    }

    /// Mid-size bucket for the grid tile.
    var thumbnailURL: String? {
        guard let imgs = media?.images else { return nil }
        return (imgs["400x300"] ?? imgs["600x"] ?? imgs["1200x"] ?? imgs["150x150"])?.url
    }

    /// Full-res for drag-out. The v5 API tops out at 1200px, but Pinterest's CDN serves
    /// the same image under an `originals/` path prefix, so rewrite the size segment to
    /// recover the true original. Falls back to the largest API bucket if there's no URL.
    var fullResURL: String? {
        guard let url = largest?.url else { return nil }
        return Self.originalsURL(from: url) ?? url
    }

    var title_: String {
        for candidate in [title, altText, description] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return ""
    }

    /// `https://i.pinimg.com/1200x/ab/cd/ef/hash.jpg` → `.../originals/ab/cd/ef/hash.jpg`.
    /// The first path segment is the size bucket; swap it for `originals`.
    static func originalsURL(from urlString: String) -> String? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        var segments = comps.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // segments[0] is "" (leading slash); segments[1] is the size bucket.
        guard segments.count > 1, !segments[1].isEmpty else { return nil }
        segments[1] = "originals"
        comps.path = segments.joined(separator: "/")
        return comps.url?.absoluteString
    }
}
