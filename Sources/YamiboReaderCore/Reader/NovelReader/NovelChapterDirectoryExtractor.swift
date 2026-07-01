import Foundation

package struct NovelChapterAnchor: Hashable, Sendable {
    package let resumePoint: ReaderResumePoint

    package init(resumePoint: ReaderResumePoint) {
        self.resumePoint = resumePoint
    }
}

package struct NovelChapterDirectoryEntry: Hashable, Sendable {
    package let chapter: ReaderChapter
    package let anchor: NovelChapterAnchor?
    package let ownerPostID: String?

    package init(
        chapter: ReaderChapter,
        anchor: NovelChapterAnchor?,
        ownerPostID: String?
    ) {
        self.chapter = chapter
        self.anchor = anchor
        self.ownerPostID = ownerPostID
    }
}

package enum NovelChapterDirectoryExtractor {
    package static func entries(
        from document: ReaderPageDocument,
        settings: ReaderAppearanceSettings
    ) -> [NovelChapterDirectoryEntry] {
        var seenIdentities: Set<NovelChapterIdentity> = []
        return document.segments.indices.compactMap { index in
            let segment = document.segments[index]
            let semantics = document.semantics(forSegmentIndex: index)
            let source = document.source(forSegmentIndex: index)
            if source?.isAuthorReplyToOther == true, !settings.showsAuthorRepliesToOthers {
                return nil
            }
            guard let semantics,
                  let chapterIdentity = semantics.chapterIdentity,
                  seenIdentities.insert(chapterIdentity).inserted else {
                return nil
            }
            let ordinal = seenIdentities.count - 1
            let title = segment.chapterTitle ?? ""
            let anchor = semantics.textSegmentIdentity.map {
                NovelChapterAnchor(
                    resumePoint: ReaderResumePoint(
                        view: document.view,
                        chapterIdentity: chapterIdentity,
                        textSegmentIdentity: $0,
                        displayedTextOffset: 0,
                        chapterOrdinal: ordinal,
                        chapterTitle: title,
                        segmentProgress: 0,
                        authorID: document.resolvedAuthorID,
                        readingModeHint: settings.readingMode
                    )
                )
            }
            return NovelChapterDirectoryEntry(
                chapter: ReaderChapter(
                    ordinal: ordinal,
                    title: title,
                    startIndex: ordinal
                ),
                anchor: anchor,
                ownerPostID: source?.ownerPostID
            )
        }
    }
}
