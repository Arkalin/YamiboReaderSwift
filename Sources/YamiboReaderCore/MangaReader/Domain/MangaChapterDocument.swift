import Foundation

public struct MangaChapterDocument: Hashable, Sendable {
    public var tid: String
    public var ownerPostID: String
    public var chapterTitle: String
    public var chapterURL: URL
    public var imageURLs: [URL]

    public init(
        tid: String,
        ownerPostID: String? = nil,
        chapterTitle: String,
        chapterURL: URL,
        imageURLs: [URL]
    ) {
        self.tid = tid
        let normalizedOwnerPostID = ownerPostID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedOwnerPostID, !normalizedOwnerPostID.isEmpty {
            self.ownerPostID = normalizedOwnerPostID
        } else {
            self.ownerPostID = tid
        }
        self.chapterTitle = chapterTitle
        self.chapterURL = chapterURL
        self.imageURLs = imageURLs
    }
}
