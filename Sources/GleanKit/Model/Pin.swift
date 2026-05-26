import Foundation

public struct Pin: Identifiable, Hashable, Sendable {
    public let id: String
    public let boardID: String
    public let title: String
    public let thumbnailURL: URL?
    public let fullResURL: URL?

    public init(id: String, boardID: String, title: String, thumbnailURL: URL?, fullResURL: URL?) {
        self.id = id
        self.boardID = boardID
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.fullResURL = fullResURL
    }
}
