import Foundation

/// Builds requests to Pinterest's internal `/resource/<Name>Resource/get/` endpoints.
/// These take a URL-encoded JSON `data` param of the form `{"options": {...}, "context": {}}`.
/// Brittle by nature — this is the single file to adjust when the format shifts.
enum Endpoints {
    static let base = "https://www.pinterest.com/resource"

    static func url(resource: String, options: [String: Any]) -> URL? {
        let payload: [String: Any] = ["options": options, "context": [:]]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        var components = URLComponents(string: "\(base)/\(resource)/get/")
        components?.queryItems = [
            URLQueryItem(name: "source_url", value: "/"),
            URLQueryItem(name: "data", value: jsonString),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        return components?.url
    }
}
