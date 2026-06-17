import Foundation

public struct MangaReadingPosition: Hashable, Sendable {
    public var tid: String
    public var localIndex: Int

    public init(tid: String, localIndex: Int) {
        self.tid = tid
        self.localIndex = max(0, localIndex)
    }
}

public struct MangaChapterWindowSnapshot: Equatable, Sendable {
    public var pages: [MangaPage]
    public var resolvedPosition: MangaReadingPosition?
    public var resolvedPageIndex: Int?

    public init(
        pages: [MangaPage],
        resolvedPosition: MangaReadingPosition?,
        resolvedPageIndex: Int?
    ) {
        self.pages = pages
        self.resolvedPosition = resolvedPosition
        self.resolvedPageIndex = resolvedPageIndex
    }
}

public enum MangaChapterWindowNoopReason: Equatable, Sendable {
    case duplicateChapter
    case notAdjacent
    case unknownChapter
}

public enum MangaChapterWindowMutationResult: Equatable, Sendable {
    case changed(MangaChapterWindowSnapshot)
    case unchanged(MangaChapterWindowSnapshot, reason: MangaChapterWindowNoopReason)
}

public struct MangaChapterWindow: Sendable {
    private var directory: MangaDirectory
    private var documents: [MangaChapterDocument]
    private var currentPosition: MangaReadingPosition?
    private let maxLoadedDocuments: Int

    public init(
        directory: MangaDirectory,
        initialDocument: MangaChapterDocument,
        position: MangaReadingPosition? = nil,
        maxLoadedDocuments: Int = 10
    ) {
        self.directory = directory
        self.documents = [initialDocument]
        self.currentPosition = position
        self.maxLoadedDocuments = max(1, maxLoadedDocuments)
    }

    public var snapshot: MangaChapterWindowSnapshot {
        makeSnapshot(position: currentPosition)
    }

    public mutating func moveToLoadedPage(at pageIndex: Int) -> MangaChapterWindowSnapshot {
        let pages = makePages()
        guard !pages.isEmpty else {
            currentPosition = nil
            return makeSnapshot(position: nil)
        }
        let clampedIndex = min(max(pageIndex, 0), pages.count - 1)
        let page = pages[clampedIndex]
        currentPosition = MangaReadingPosition(tid: page.tid, localIndex: page.localIndex)
        return makeSnapshot(position: currentPosition)
    }

    public mutating func updateDirectory(
        _ directory: MangaDirectory,
        preserving position: MangaReadingPosition?
    ) -> MangaChapterWindowSnapshot {
        self.directory = directory
        reorderDocumentsToMatchDirectory()
        currentPosition = position
        return makeSnapshot(position: position)
    }

    public mutating func insertAdjacentDocument(
        _ document: MangaChapterDocument
    ) -> MangaChapterWindowMutationResult {
        insertAdjacentDocument(document, preserving: currentPosition)
    }

    public mutating func insertAdjacentDocument(
        _ document: MangaChapterDocument,
        preserving position: MangaReadingPosition?
    ) -> MangaChapterWindowMutationResult {
        guard documents.contains(where: { $0.tid == document.tid }) == false else {
            let snapshot = makeSnapshot(position: position)
            return .unchanged(snapshot, reason: .duplicateChapter)
        }
        guard directory.chapters.contains(where: { $0.tid == document.tid }) else {
            let snapshot = makeSnapshot(position: position)
            return .unchanged(snapshot, reason: .unknownChapter)
        }
        guard isAdjacentToLoadedRange(document.tid) else {
            let snapshot = makeSnapshot(position: position)
            return .unchanged(snapshot, reason: .notAdjacent)
        }

        documents.append(document)
        reorderDocumentsToMatchDirectory()
        trimDocuments(preserving: position?.tid ?? document.tid)
        currentPosition = position
        return .changed(makeSnapshot(position: position))
    }

    public mutating func reset(
        to document: MangaChapterDocument,
        position: MangaReadingPosition?
    ) -> MangaChapterWindowSnapshot {
        documents = [document]
        currentPosition = position
        return makeSnapshot(position: position)
    }

    public func adjacentChapter(
        from position: MangaReadingPosition,
        delta: Int
    ) -> MangaChapter? {
        guard delta != 0,
              let index = directory.chapters.firstIndex(where: { $0.tid == position.tid }) else {
            return nil
        }
        let target = index + delta
        guard directory.chapters.indices.contains(target) else { return nil }
        return directory.chapters[target]
    }

    public func adjacentChapterForLoadedRange(delta: Int) -> MangaChapter? {
        guard delta != 0 else { return nil }
        let anchorTID = delta < 0 ? documents.first?.tid : documents.last?.tid
        guard let anchorTID,
              let index = directory.chapters.firstIndex(where: { $0.tid == anchorTID }) else {
            return nil
        }
        let target = index + delta
        guard directory.chapters.indices.contains(target) else { return nil }
        return directory.chapters[target]
    }

    private func makeSnapshot(position: MangaReadingPosition?) -> MangaChapterWindowSnapshot {
        let pages = makePages()
        let resolved = resolve(position, in: pages)
        return MangaChapterWindowSnapshot(
            pages: pages,
            resolvedPosition: resolved?.position,
            resolvedPageIndex: resolved?.pageIndex
        )
    }

    private func makePages() -> [MangaPage] {
        var pages: [MangaPage] = []
        pages.reserveCapacity(documents.reduce(0) { $0 + $1.pages.count })

        for document in documents {
            for (localIndex, imageURL) in document.pages.enumerated() {
                pages.append(
                    MangaPage(
                        tid: document.tid,
                        ownerPostID: document.ownerPostID,
                        chapterTitle: document.chapterTitle,
                        imageURL: imageURL,
                        globalIndex: pages.count,
                        localIndex: localIndex,
                        chapterTotalPages: document.pages.count,
                        chapterURL: document.chapterURL
                    )
                )
            }
        }

        return pages
    }

    private func isAdjacentToLoadedRange(_ tid: String) -> Bool {
        guard let first = documents.first?.tid,
              let last = documents.last?.tid,
              let targetIndex = directory.chapters.firstIndex(where: { $0.tid == tid }),
              let firstIndex = directory.chapters.firstIndex(where: { $0.tid == first }),
              let lastIndex = directory.chapters.firstIndex(where: { $0.tid == last }) else {
            return false
        }
        return targetIndex == firstIndex - 1 || targetIndex == lastIndex + 1
    }

    private mutating func reorderDocumentsToMatchDirectory() {
        let order = Dictionary(uniqueKeysWithValues: directory.chapters.enumerated().map { ($1.tid, $0) })
        documents.sort {
            (order[$0.tid] ?? .max) < (order[$1.tid] ?? .max)
        }
    }

    private mutating func trimDocuments(preserving tid: String) {
        while documents.count > maxLoadedDocuments {
            if documents.first?.tid != tid {
                documents.removeFirst()
            } else if documents.last?.tid != tid {
                documents.removeLast()
            } else {
                return
            }
        }
    }

    private func resolve(
        _ position: MangaReadingPosition?,
        in pages: [MangaPage]
    ) -> (position: MangaReadingPosition, pageIndex: Int)? {
        guard let position else { return nil }
        let chapterPages = pages.filter { $0.tid == position.tid }
        guard !chapterPages.isEmpty else { return nil }
        let localIndex = min(max(position.localIndex, 0), max(chapterPages.count - 1, 0))
        guard let pageIndex = pages.firstIndex(where: { $0.tid == position.tid && $0.localIndex == localIndex }) else {
            return nil
        }
        return (MangaReadingPosition(tid: position.tid, localIndex: localIndex), pageIndex)
    }
}
