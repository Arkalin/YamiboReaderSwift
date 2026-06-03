import Foundation
import CoreGraphics

public enum NovelTextLayoutFailure: LocalizedError, Equatable, Sendable {
    case unableToLayoutText

    public var errorDescription: String? {
        switch self {
        case .unableToLayoutText:
            return "Novel Text Layout could not produce rendered text."
        }
    }
}

public typealias NovelTextPagination = @Sendable (
    _ document: ReaderPageDocument,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) throws -> ReaderPaginationResult

public enum ReaderPaginator {
    public static func paginate(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> ReaderPaginationResult {
        (try? paginateNovelTextLayout(document: document, settings: settings, layout: layout))
            ?? emptyPagination(documentView: document.view)
    }

    public static func paginateNovelTextLayout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> ReaderPaginationResult {
        try paginateNovelTextLayout(
            document: document,
            settings: settings,
            layout: layout,
            pagedLayout: nil,
            verticalLayout: nil,
            requiresAuthoritativePagedLayout: nil,
            requiresAuthoritativeVerticalLayout: nil
        )
    }

    static func paginateNovelTextLayout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        pagedLayout: NovelPagedTextLayout? = nil,
        verticalLayout: NovelVerticalTextLayout? = nil,
        requiresAuthoritativePagedLayout: Bool? = nil,
        requiresAuthoritativeVerticalLayout: Bool? = nil
    ) throws -> ReaderPaginationResult {
        let annotatedSegments = annotatedSegments(from: document, settings: settings)
        let result = try paginate(
            annotatedSegments: annotatedSegments,
            document: document,
            settings: settings,
            layout: layout,
            chunker: { annotatedSegment, settings, layout in
                try NovelTextLayout.renderedTextSlices(
                    annotatedSegment.textContent,
                    chapterTitle: annotatedSegment.chapterTitle,
                    settings: settings,
                    layout: layout,
                    readingMode: settings.readingMode,
                    requiresAuthoritativePagedLayout: requiresAuthoritativePagedLayout ?? Self.requiresAuthoritativePagedLayout(for: settings),
                    requiresAuthoritativeVerticalLayout: requiresAuthoritativeVerticalLayout ?? Self.requiresAuthoritativeVerticalLayout(for: settings),
                    pagedLayout: pagedLayout,
                    verticalLayout: verticalLayout
                )
            }
        )
        let hasVisibleText = result.pages.contains { page in
            page.blocks.contains { block in
                guard case let .text(text, _, _) = block else { return false }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        let hasInputText = document.segments.contains { segment in
            guard case let .text(text, _) = segment else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !hasInputText || hasVisibleText else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        return result
    }

    private static func requiresAuthoritativePagedLayout(for settings: ReaderAppearanceSettings) -> Bool {
#if canImport(UIKit) || canImport(AppKit)
        settings.readingMode == .paged
#else
        false
#endif
    }

    private static func requiresAuthoritativeVerticalLayout(for settings: ReaderAppearanceSettings) -> Bool {
#if canImport(UIKit) || canImport(AppKit)
        settings.readingMode == .vertical
#else
        false
#endif
    }

    private static func paginate(
        annotatedSegments: [AnnotatedSegment],
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        chunker: (AnnotatedSegment, ReaderAppearanceSettings, ReaderContainerLayout) throws -> [TextSlice]
    ) throws -> ReaderPaginationResult {
        var pages: [ReaderRenderedPage] = []
        var chapters: [ReaderChapter] = []
        var seenChapterOrdinals = Set<Int>()

        for annotatedSegment in annotatedSegments {
            switch annotatedSegment.segment {
            case let .text(text, chapterTitle):
                let slices = try chunker(annotatedSegment, settings, layout)
                for slice in slices where !slice.text.isEmpty {
                    if settings.readingMode == .paged,
                       appendTextSliceToPreviousPageIfPossible(
                           slice,
                           chapterTitle: chapterTitle,
                           annotatedSegment: annotatedSegment,
                           document: document,
                           settings: settings,
                           layout: layout,
                           pages: &pages
                       ) {
                        continue
                    }

                    let page = ReaderRenderedPage(
                        index: pages.count,
                        blocks: [
                            .text(
                                slice.text,
                                chapterTitle: chapterTitle,
                                startsAtParagraphBoundary: slice.startsAtParagraphBoundary
                            ),
                        ],
                        documentView: document.view,
                        chapterOrdinal: annotatedSegment.chapterOrdinal,
                        chapterTitle: annotatedSegment.chapterTitle,
                        segmentIndex: annotatedSegment.index,
                        segmentStartOffset: slice.startOffset,
                        segmentEndOffset: slice.endOffset,
                        textRanges: [
                            ReaderRenderedTextRange(
                                segmentIndex: annotatedSegment.index,
                                startOffset: slice.startOffset,
                                endOffset: slice.endOffset
                            )
                        ],
                        chapterCommentTarget: chapterCommentTarget(for: annotatedSegment, document: document)
                    )
                    if let chapterOrdinal = annotatedSegment.chapterOrdinal,
                       let chapterTitle = annotatedSegment.chapterTitle,
                       seenChapterOrdinals.insert(chapterOrdinal).inserted {
                        chapters.append(
                            ReaderChapter(
                                ordinal: chapterOrdinal,
                                title: chapterTitle,
                                startIndex: page.index,
                                chapterCommentTarget: page.chapterCommentTarget
                            )
                        )
                    }
                    pages.append(page)
                }

                if pages.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pages.append(
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [.text(text, chapterTitle: chapterTitle)],
                            documentView: document.view,
                            chapterOrdinal: annotatedSegment.chapterOrdinal,
                            chapterTitle: annotatedSegment.chapterTitle,
                            segmentIndex: annotatedSegment.index,
                            segmentStartOffset: 0,
                            segmentEndOffset: text.count,
                            textRanges: [
                                ReaderRenderedTextRange(
                                    segmentIndex: annotatedSegment.index,
                                    startOffset: 0,
                                    endOffset: text.count
                                )
                            ],
                            chapterCommentTarget: chapterCommentTarget(for: annotatedSegment, document: document)
                        )
                    )
                }
            case let .image(url, chapterTitle):
                let page = ReaderRenderedPage(
                    index: pages.count,
                    blocks: [.image(url, chapterTitle: chapterTitle)],
                    documentView: document.view,
                    chapterOrdinal: annotatedSegment.chapterOrdinal,
                    chapterTitle: annotatedSegment.chapterTitle,
                    segmentIndex: annotatedSegment.index,
                    segmentStartOffset: 0,
                    segmentEndOffset: 0,
                    chapterCommentTarget: chapterCommentTarget(for: annotatedSegment, document: document)
                )
                if let chapterOrdinal = annotatedSegment.chapterOrdinal,
                   let chapterTitle = annotatedSegment.chapterTitle,
                   seenChapterOrdinals.insert(chapterOrdinal).inserted {
                    chapters.append(
                        ReaderChapter(
                            ordinal: chapterOrdinal,
                            title: chapterTitle,
                            startIndex: page.index,
                            chapterCommentTarget: page.chapterCommentTarget
                        )
                    )
                }
                pages.append(page)
            }
        }

        if pages.isEmpty {
            pages = [ReaderRenderedPage(index: 0, blocks: [.footer(L10n.string("reader.empty_content"))], documentView: document.view)]
        }

        return ReaderPaginationResult(pages: pages, chapters: chapters)
    }

    private static func appendTextSliceToPreviousPageIfPossible(
        _ slice: TextSlice,
        chapterTitle: String?,
        annotatedSegment: AnnotatedSegment,
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        pages: inout [ReaderRenderedPage]
    ) -> Bool {
        guard !pages.isEmpty else { return false }
        let previousIndex = pages.count - 1
        var previousPage = pages[previousIndex]
        guard previousPage.documentView > 0,
              previousPage.chapterOrdinal == annotatedSegment.chapterOrdinal,
              previousPage.chapterTitle == annotatedSegment.chapterTitle,
              previousPage.chapterCommentTarget == chapterCommentTarget(for: annotatedSegment, document: document),
              previousPage.blocks.allSatisfy(\.isTextBlock) else {
            return false
        }

        let combinedText = (previousPage.blocks.compactMap(\.textContent) + [slice.text])
            .joined(separator: "\n\n")

        guard NovelTextLayout.textFits(
            combinedText,
            chapterTitle: previousPage.chapterTitle,
            settings: settings,
            layout: layout
        ) else {
            return false
        }

        previousPage.blocks.append(
            .text(
                slice.text,
                chapterTitle: chapterTitle,
                startsAtParagraphBoundary: slice.startsAtParagraphBoundary
            )
        )
        previousPage.textRanges.append(
            ReaderRenderedTextRange(
                segmentIndex: annotatedSegment.index,
                startOffset: slice.startOffset,
                endOffset: slice.endOffset
            )
        )
        previousPage.segmentEndOffset = max(previousPage.segmentEndOffset, slice.endOffset)
        pages[previousIndex] = previousPage
        return true
    }

    private static func emptyPagination(documentView: Int) -> ReaderPaginationResult {
        ReaderPaginationResult(
            pages: [
                ReaderRenderedPage(
                    index: 0,
                    blocks: [.footer(L10n.string("reader.empty_content"))],
                    documentView: documentView
                )
            ],
            chapters: []
        )
    }

    private static func annotatedSegments(
        from document: ReaderPageDocument,
        settings: ReaderAppearanceSettings
    ) -> [AnnotatedSegment] {
        var results: [AnnotatedSegment] = []
        var currentChapterTitle: String?
        var currentChapterOrdinal: Int?
        var nextChapterOrdinal = 0

        for (index, segment) in document.segments.enumerated() {
            guard let transformedSegment = transformedSegment(from: segment, settings: settings) else {
                continue
            }
            let explicitChapterTitle = segment.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let explicitChapterTitle, !explicitChapterTitle.isEmpty {
                if currentChapterTitle != explicitChapterTitle {
                    currentChapterTitle = explicitChapterTitle
                    currentChapterOrdinal = nextChapterOrdinal
                    nextChapterOrdinal += 1
                }
            }

            results.append(
                AnnotatedSegment(
                    index: index,
                    segment: transformedSegment,
                    chapterOrdinal: currentChapterOrdinal,
                    chapterTitle: currentChapterTitle
                )
            )
        }

        return results
    }

    private static func transformedSegment(
        from segment: ReaderSegment,
        settings: ReaderAppearanceSettings
    ) -> ReaderSegment? {
        switch segment {
        case let .text(text, chapterTitle):
            let transformed = ReaderTextTransformer.transform(text, mode: settings.translationMode)
            return .text(transformed, chapterTitle: chapterTitle)
        case let .image(url, chapterTitle):
            return settings.loadsInlineImages ? .image(url, chapterTitle: chapterTitle) : nil
        }
    }

    private static func chapterCommentTarget(
        for annotatedSegment: AnnotatedSegment,
        document: ReaderPageDocument
    ) -> ReaderChapterCommentTarget? {
        guard let ownerPostID = document.source(forSegmentIndex: annotatedSegment.index)?.ownerPostID,
              !ownerPostID.isEmpty else {
            return nil
        }
        return ReaderChapterCommentTarget(
            threadURL: document.threadURL,
            view: document.view,
            ownerPostID: ownerPostID,
            title: annotatedSegment.chapterTitle,
            authorID: document.contentSource.isAuthorFiltered ? document.resolvedAuthorID : nil
        )
    }
}

private struct AnnotatedSegment {
    let index: Int
    let segment: ReaderSegment
    let chapterOrdinal: Int?
    let chapterTitle: String?

    var textContent: String {
        guard case let .text(text, _) = segment else { return "" }
        return text
    }
}
