import Foundation

/// `{"resource_response": {"data": <T>, "bookmark": <String?>}}`
struct ResourceEnvelope<T: Decodable>: Decodable {
    struct Response: Decodable {
        let data: T
        let bookmark: String?
    }
    let resourceResponse: Response

    enum CodingKeys: String, CodingKey { case resourceResponse = "resource_response" }
}

/// Decodes an element, yielding nil instead of throwing — board feeds mix pins with
/// non-pin modules (stories, separators), so one odd item shouldn't drop the batch.
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct PinterestBoard: Decodable, Sendable {
    let id: String
    let name: String
    let url: String
}

struct PinterestImage: Decodable, Sendable {
    let url: String
    let width: Int?
    let height: Int?
}

struct PinterestPin: Decodable, Sendable {
    let id: String
    let images: [String: PinterestImage]?
    let gridTitle: String?
    let seoAltText: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, images, description
        case gridTitle = "grid_title"
        case seoAltText = "seo_alt_text"
    }

    var thumbnailURL: String? { images?["236x"]?.url ?? images?["474x"]?.url }
    var fullResURL: String? { images?["orig"]?.url ?? images?["736x"]?.url }

    var title: String {
        if let gridTitle, !gridTitle.isEmpty { return gridTitle }
        if let seoAltText, !seoAltText.isEmpty { return seoAltText }
        return description ?? ""
    }
}
