public struct MangaChapterWindow: Hashable, Sendable {
    public private(set) var documents: [MangaChapterDocument]
    public private(set) var position: MangaReadingPosition?

    public init(initialDocument: MangaChapterDocument, position: MangaReadingPosition? = nil) {
        self.documents = [initialDocument]
        self.position = nil
        self.position = clampedPosition(position)
    }

    public init?(documents: [MangaChapterDocument], position: MangaReadingPosition? = nil) {
        guard !documents.isEmpty else { return nil }
        self.documents = documents
        self.position = nil
        self.position = clampedPosition(position)
    }

    public var resolvedPosition: MangaReadingPosition? {
        clampedPosition(position)
    }

    public mutating func updatePosition(_ position: MangaReadingPosition?) {
        self.position = clampedPosition(position)
    }

    public func clampedPosition(_ position: MangaReadingPosition?) -> MangaReadingPosition? {
        guard let position,
              let document = documents.first(where: { $0.tid == position.tid }),
              !document.imageURLs.isEmpty else {
            return nil
        }

        return MangaReadingPosition(
            tid: position.tid,
            localIndex: min(max(position.localIndex, 0), document.imageURLs.count - 1)
        )
    }
}
