import Foundation
import YamiboReaderCore

public struct MangaViewportRequest: Equatable, Sendable {
    public var targetIndex: Int
    public var targetPageID: MangaPage.ID
    public var animated: Bool
    public var revision: UUID

    public init(targetIndex: Int, targetPageID: MangaPage.ID, animated: Bool, revision: UUID) {
        self.targetIndex = targetIndex
        self.targetPageID = targetPageID
        self.animated = animated
        self.revision = revision
    }
}

public struct MangaPagedSpread: Identifiable, Equatable, Sendable {
    public let index: Int
    public let leftPageIndex: Int
    public let rightPageIndex: Int?
    public let chapterTitle: String

    public var id: Int { index }

    public init(index: Int, leftPageIndex: Int, rightPageIndex: Int?, chapterTitle: String) {
        self.index = max(0, index)
        self.leftPageIndex = max(0, leftPageIndex)
        self.rightPageIndex = rightPageIndex
        self.chapterTitle = chapterTitle
    }
}
