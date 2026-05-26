import Foundation

public struct Board: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: String

    public init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}
