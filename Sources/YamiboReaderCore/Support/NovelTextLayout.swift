import CoreGraphics
import Foundation

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

typealias NovelPagedTextLayout = @Sendable (
    _ text: String,
    _ chapterTitle: String?,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) -> [TextSlice]

typealias NovelVerticalTextLayout = @Sendable (
    _ text: String,
    _ chapterTitle: String?,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) -> [TextSlice]

public enum NovelTextLayout {
    private static let viewportIndexCache = NovelTextViewportIndexCache()

    public static func displayValue(
        viewportContext: NovelTextViewportContext,
        viewportPage: NovelTextViewportIndexPage,
        settings: ReaderAppearanceSettings
    ) throws -> NovelTextDisplayValue {
        let text = try viewportPage.ranges.map { range in
            try viewportText(
                for: range,
                viewportContext: viewportContext
            )
        }
        .joined(separator: "\n\n")
        guard !text.isEmpty else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        return NovelTextDisplayValue(
            text: text,
            chapterTitle: viewportPage.chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary(
                viewportContext: viewportContext,
                viewportPage: viewportPage
            ),
            settings: settings,
            ranges: viewportPage.ranges
        )
    }

    public static func renderedPages(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        try self.layout(
            document: document,
            settings: settings,
            layout: layout,
            requiresAuthoritativePagedLayout: nil,
            requiresAuthoritativeVerticalLayout: nil
        )
    }

    public static func layout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        try self.layout(
            document: document,
            settings: settings,
            layout: layout,
            requiresAuthoritativePagedLayout: nil,
            requiresAuthoritativeVerticalLayout: nil
        )
    }

    static func renderedPages(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        requiresAuthoritativePagedLayout: Bool? = nil,
        requiresAuthoritativeVerticalLayout: Bool? = nil,
        pagedLayout: NovelPagedTextLayout? = nil,
        verticalLayout: NovelVerticalTextLayout? = nil,
        usesViewportIndexCache: Bool? = nil
    ) throws -> NovelTextLayoutResult {
        try self.layout(
            document: document,
            settings: settings,
            layout: layout,
            requiresAuthoritativePagedLayout: requiresAuthoritativePagedLayout,
            requiresAuthoritativeVerticalLayout: requiresAuthoritativeVerticalLayout,
            pagedLayout: pagedLayout,
            verticalLayout: verticalLayout,
            usesViewportIndexCache: usesViewportIndexCache
        )
    }

    static func layout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        requiresAuthoritativePagedLayout: Bool? = nil,
        requiresAuthoritativeVerticalLayout: Bool? = nil,
        pagedLayout: NovelPagedTextLayout? = nil,
        verticalLayout: NovelVerticalTextLayout? = nil,
        usesViewportIndexCache: Bool? = nil
    ) throws -> NovelTextLayoutResult {
        let cacheKey = NovelTextViewportIndexCacheKey(
            document: document,
            settings: settings,
            layout: layout
        )
        let shouldUseCache = usesViewportIndexCache ?? (pagedLayout == nil && verticalLayout == nil)
        if shouldUseCache, let cachedResult = viewportIndexCache.result(for: cacheKey) {
            return cachedResult
        }
        let annotatedSegments = annotatedSegments(from: document, settings: settings)
        let viewportContextSeed = makeViewportContext(
            annotatedSegments: annotatedSegments,
            document: document,
            settings: settings,
            layout: layout
        )
        let result = try render(
            annotatedSegments: annotatedSegments,
            document: document,
            settings: settings,
            layout: layout,
            viewportContextSeed: viewportContextSeed,
            chunker: { text, chapterTitle, settings, layout in
                try renderedTextSlices(
                    text,
                    chapterTitle: chapterTitle,
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
        let hasVisibleText = result.viewportIndex.pages.contains { !$0.ranges.isEmpty }
        let hasInputText = document.segments.contains { segment in
            guard case let .text(text, _) = segment else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !hasInputText || hasVisibleText else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        if shouldUseCache {
            viewportIndexCache.store(result, for: cacheKey)
        }
        return result
    }

    static func renderedTextSlices(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        readingMode: ReaderReadingMode,
        requiresAuthoritativePagedLayout: Bool,
        requiresAuthoritativeVerticalLayout: Bool = false,
        pagedLayout: NovelPagedTextLayout? = nil,
        verticalLayout: NovelVerticalTextLayout? = nil
    ) throws -> [TextSlice] {
        switch readingMode {
        case .paged:
            return try pagedTextSlices(
                text,
                chapterTitle: chapterTitle,
                settings: settings,
                layout: layout,
                requiresAuthoritativeLayout: requiresAuthoritativePagedLayout,
                pagedLayout: pagedLayout
            )
        case .vertical:
            return try verticalTextChunks(
                text,
                chapterTitle: chapterTitle,
                settings: settings,
                layout: layout,
                requiresAuthoritativeLayout: requiresAuthoritativeVerticalLayout,
                verticalLayout: verticalLayout
            )
        }
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

    private static func render(
        annotatedSegments: [NovelAnnotatedSegment],
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        viewportContextSeed: NovelTextViewportContext,
        chunker: (String, String?, ReaderAppearanceSettings, ReaderContainerLayout) throws -> [TextSlice]
    ) throws -> NovelTextLayoutResult {
        var pages: [NovelTextViewportIndexPage] = []
        var chapters: [NovelTextViewportIndexChapter] = []
        var seenChapterOrdinals = Set<Int>()
        let annotatedSegmentByIndex = Dictionary(
            uniqueKeysWithValues: annotatedSegments.map { ($0.index, $0) }
        )
        let imageSegmentIndexes = Set(annotatedSegments.compactMap { annotatedSegment in
            if case .image = annotatedSegment.segment {
                return annotatedSegment.index
            }
            return nil
        })
        var pageDrafts: [NovelViewportPageDraft] = []
        var nextDraftOrdinal = 0

        if !viewportContextSeed.document.text.isEmpty {
            let slices = try chunker(viewportContextSeed.document.text, nil, settings, layout)
            for slice in slices where !slice.text.isEmpty {
                let ranges = segmentRanges(
                    for: slice,
                    viewportDocument: viewportContextSeed.document
                )
                for group in splitTextRanges(
                    ranges,
                    aroundImageSegmentIndexes: imageSegmentIndexes,
                    annotatedSegmentByIndex: annotatedSegmentByIndex,
                    document: document
                ) where !group.isEmpty {
                    pageDrafts.append(
                        NovelViewportPageDraft(
                            orderSegmentIndex: group[0].segmentIndex,
                            ordinal: nextDraftOrdinal,
                            kind: .text(group)
                        )
                    )
                    nextDraftOrdinal += 1
                }
            }
        }

        for annotatedSegment in annotatedSegments {
            switch annotatedSegment.segment {
            case .text:
                continue

            case let .image(url, chapterTitle):
                let externalBlock = NovelTextViewportExternalBlock(
                    segmentIndex: annotatedSegment.index,
                    url: url,
                    chapterOrdinal: annotatedSegment.chapterOrdinal,
                    chapterTitle: annotatedSegment.chapterTitle,
                    chapterCommentTarget: chapterCommentTarget(for: annotatedSegment, document: document)
                )
                pageDrafts.append(
                    NovelViewportPageDraft(
                        orderSegmentIndex: annotatedSegment.index,
                        ordinal: nextDraftOrdinal,
                        kind: .image(url: url, chapterTitle: chapterTitle, externalBlock: externalBlock)
                    )
                )
                nextDraftOrdinal += 1
            }
        }

        for draft in pageDrafts.sorted(by: {
            if $0.orderSegmentIndex != $1.orderSegmentIndex {
                return $0.orderSegmentIndex < $1.orderSegmentIndex
            }
            return $0.ordinal < $1.ordinal
        }) {
            switch draft.kind {
            case let .text(ranges):
                guard let firstRange = ranges.first,
                      let annotatedSegment = annotatedSegmentByIndex[firstRange.segmentIndex] else {
                    continue
                }
                let page = NovelTextViewportIndexPage(
                    pageIndex: pages.count,
                    documentView: document.view,
                    chapterOrdinal: annotatedSegment.chapterOrdinal,
                    chapterTitle: annotatedSegment.chapterTitle,
                    ranges: ranges,
                    externalBlocks: [],
                    chapterCommentTarget: chapterCommentTarget(for: annotatedSegment, document: document)
                )
                if let chapterOrdinal = annotatedSegment.chapterOrdinal,
                   let chapterTitle = annotatedSegment.chapterTitle,
                   seenChapterOrdinals.insert(chapterOrdinal).inserted {
                    chapters.append(
                        NovelTextViewportIndexChapter(
                            ordinal: chapterOrdinal,
                            title: chapterTitle,
                            startPageIndex: page.pageIndex,
                            chapterCommentTarget: page.chapterCommentTarget
                        )
                    )
                }
                pages.append(page)

            case let .image(_, _, externalBlock):
                let page = NovelTextViewportIndexPage(
                    pageIndex: pages.count,
                    documentView: document.view,
                    chapterOrdinal: externalBlock.chapterOrdinal,
                    chapterTitle: externalBlock.chapterTitle,
                    ranges: [],
                    externalBlocks: [externalBlock],
                    chapterCommentTarget: externalBlock.chapterCommentTarget
                )
                if let chapterOrdinal = externalBlock.chapterOrdinal,
                   let chapterTitle = externalBlock.chapterTitle,
                   seenChapterOrdinals.insert(chapterOrdinal).inserted {
                    chapters.append(
                        NovelTextViewportIndexChapter(
                            ordinal: chapterOrdinal,
                            title: chapterTitle,
                            startPageIndex: page.pageIndex,
                            chapterCommentTarget: page.chapterCommentTarget
                        )
                    )
                }
                pages.append(page)
            }
        }

        if pages.isEmpty {
            pages = [
                NovelTextViewportIndexPage(
                    pageIndex: 0,
                    documentView: document.view,
                    chapterOrdinal: nil,
                    chapterTitle: nil,
                    ranges: []
                )
            ]
        }

        let viewportIndex = NovelTextViewportIndex(
            documentView: document.view,
            readingMode: settings.readingMode,
            pages: pages,
            chapters: chapters
        )
        let viewportContext = NovelTextViewportContext(
            identity: viewportContextSeed.identity,
            document: viewportContextSeed.document,
            externalBlocks: viewportContextSeed.externalBlocks,
            diagnostics: NovelTextViewportDiagnostics(
                indexBuildCount: viewportContextSeed.diagnostics.indexBuildCount,
                visibleLayoutPassCount: viewportContextSeed.diagnostics.visibleLayoutPassCount,
                compatibilityRenderedPageCount: pages.count,
                compatibilityTextDisplayValueCount: 0
            )
        )

        return NovelTextLayoutResult(
            viewportContext: viewportContext,
            viewportIndex: viewportIndex
        )
    }

    private static func makeViewportContext(
        annotatedSegments: [NovelAnnotatedSegment],
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> NovelTextViewportContext {
        var composedText = ""
        var textRangesBySegment: [Int: ReaderRenderedTextRange] = [:]
        var insertedSeparatorRanges: [ReaderRenderedTextRange] = []
        var externalBlocks: [NovelTextViewportExternalBlock] = []
        var lastTextSegmentIndex: Int?

        for annotatedSegment in annotatedSegments {
            switch annotatedSegment.segment {
            case let .text(text, _):
                if !composedText.isEmpty {
                    let separatorStart = composedText.count
                    composedText.append("\n\n")
                    if let lastTextSegmentIndex {
                        insertedSeparatorRanges.append(
                            ReaderRenderedTextRange(
                                segmentIndex: lastTextSegmentIndex,
                                startOffset: separatorStart,
                                endOffset: composedText.count
                            )
                        )
                    }
                }
                let startOffset = composedText.count
                composedText.append(text)
                textRangesBySegment[annotatedSegment.index] = ReaderRenderedTextRange(
                    segmentIndex: annotatedSegment.index,
                    startOffset: startOffset,
                    endOffset: composedText.count
                )
                lastTextSegmentIndex = annotatedSegment.index

            case let .image(url, _):
                externalBlocks.append(
                    NovelTextViewportExternalBlock(
                        segmentIndex: annotatedSegment.index,
                        url: url,
                        chapterOrdinal: annotatedSegment.chapterOrdinal,
                        chapterTitle: annotatedSegment.chapterTitle,
                        chapterCommentTarget: chapterCommentTarget(for: annotatedSegment, document: document)
                    )
                )
            }
        }

        return NovelTextViewportContext(
            identity: NovelTextViewportIdentity(
                threadURL: document.threadURL,
                documentView: document.view,
                maxView: document.maxView,
                fetchedAt: document.fetchedAt,
                contentSource: document.contentSource,
                appearance: settings,
                layout: layout
            ),
            document: NovelTextViewportDocument(
                text: composedText,
                textRangesBySegment: textRangesBySegment,
                insertedSeparatorRanges: insertedSeparatorRanges
            ),
            externalBlocks: externalBlocks,
            diagnostics: NovelTextViewportDiagnostics(indexBuildCount: 1)
        )
    }

    private static func segmentRanges(
        for slice: TextSlice,
        viewportDocument: NovelTextViewportDocument
    ) -> [ReaderRenderedTextRange] {
        let sliceStart = max(0, slice.startOffset)
        let sliceEnd = max(sliceStart, slice.endOffset)
        guard sliceEnd > sliceStart else { return [] }

        return viewportDocument.textRangesBySegment
            .sorted { $0.value.startOffset < $1.value.startOffset }
            .compactMap { segmentIndex, segmentRange in
                let intersectionStart = max(sliceStart, segmentRange.startOffset)
                let intersectionEnd = min(sliceEnd, segmentRange.endOffset)
                guard intersectionEnd > intersectionStart else { return nil }
                return ReaderRenderedTextRange(
                    segmentIndex: segmentIndex,
                    startOffset: intersectionStart - segmentRange.startOffset,
                    endOffset: intersectionEnd - segmentRange.startOffset
                )
            }
    }

    private static func splitTextRanges(
        _ ranges: [ReaderRenderedTextRange],
        aroundImageSegmentIndexes imageSegmentIndexes: Set<Int>,
        annotatedSegmentByIndex: [Int: NovelAnnotatedSegment],
        document: ReaderPageDocument
    ) -> [[ReaderRenderedTextRange]] {
        guard !ranges.isEmpty else { return [] }

        var groups: [[ReaderRenderedTextRange]] = []
        var currentGroup: [ReaderRenderedTextRange] = []
        var previousSegmentIndex: Int?

        for range in ranges {
            if let previousSegmentIndex,
               !currentGroup.isEmpty,
               shouldStartNewTextRangeGroup(
                   previousSegmentIndex: previousSegmentIndex,
                   nextSegmentIndex: range.segmentIndex,
                   imageSegmentIndexes: imageSegmentIndexes,
                   annotatedSegmentByIndex: annotatedSegmentByIndex,
                   document: document
               ) {
                groups.append(currentGroup)
                currentGroup = []
            }
            currentGroup.append(range)
            previousSegmentIndex = range.segmentIndex
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        return groups
    }

    private static func shouldStartNewTextRangeGroup(
        previousSegmentIndex: Int,
        nextSegmentIndex: Int,
        imageSegmentIndexes: Set<Int>,
        annotatedSegmentByIndex: [Int: NovelAnnotatedSegment],
        document: ReaderPageDocument
    ) -> Bool {
        if imageSegmentIndexes.contains(where: { imageSegmentIndex in
            imageSegmentIndex > previousSegmentIndex && imageSegmentIndex < nextSegmentIndex
        }) {
            return true
        }
        let previousSegment = annotatedSegmentByIndex[previousSegmentIndex]
        let nextSegment = annotatedSegmentByIndex[nextSegmentIndex]
        return previousSegment?.chapterOrdinal != nextSegment?.chapterOrdinal ||
            previousSegment?.chapterTitle != nextSegment?.chapterTitle ||
            previousSegment.flatMap { chapterCommentTarget(for: $0, document: document) } !=
            nextSegment.flatMap { chapterCommentTarget(for: $0, document: document) }
    }

    private static func text(
        for range: ReaderRenderedTextRange,
        annotatedTextBySegment: [Int: String]
    ) -> String? {
        guard let text = annotatedTextBySegment[range.segmentIndex] else { return nil }
        let startOffset = min(max(range.startOffset, 0), text.count)
        let endOffset = min(max(range.endOffset, startOffset), text.count)
        guard endOffset > startOffset,
              let startIndex = text.index(text.startIndex, offsetBy: startOffset, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: endOffset, limitedBy: text.endIndex) else {
            return nil
        }
        return String(text[startIndex..<endIndex])
    }

    private static func viewportText(
        for range: ReaderRenderedTextRange,
        viewportContext: NovelTextViewportContext
    ) throws -> String {
        guard let segmentRange = viewportContext.document.textRangesBySegment[range.segmentIndex] else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        guard range.startOffset >= 0,
              range.endOffset > range.startOffset,
              range.endOffset <= segmentRange.length else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        let globalStart = segmentRange.startOffset + range.startOffset
        let globalEnd = segmentRange.startOffset + range.endOffset
        return try viewportSubstring(
            in: viewportContext.document.text,
            startOffset: globalStart,
            endOffset: globalEnd
        )
    }

    private static func viewportSubstring(
        in text: String,
        startOffset: Int,
        endOffset: Int
    ) throws -> String {
        guard startOffset >= 0,
              endOffset > startOffset,
              endOffset <= text.count,
              let startIndex = text.index(text.startIndex, offsetBy: startOffset, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: endOffset, limitedBy: text.endIndex) else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        return String(text[startIndex..<endIndex])
    }

    private static func startsAtParagraphBoundary(
        viewportContext: NovelTextViewportContext,
        viewportPage: NovelTextViewportIndexPage
    ) -> Bool {
        guard let firstRange = viewportPage.ranges.first,
              let segmentRange = viewportContext.document.textRangesBySegment[firstRange.segmentIndex] else {
            return true
        }
        guard firstRange.startOffset > 0 else {
            return true
        }
        let globalStart = segmentRange.startOffset + firstRange.startOffset
        return isParagraphBoundary(in: viewportContext.document.text, at: globalStart)
    }

    private static func isParagraphBoundary(in text: String, at offset: Int) -> Bool {
        guard offset > 0, offset <= text.count else { return offset == 0 }
        let nsText = text as NSString
        var index = offset - 1
        var newlineCount = 0

        while index >= 0 {
            let character = nsText.substring(with: NSRange(location: index, length: 1))
            if character == "\n" || character == "\r" {
                newlineCount += 1
                if newlineCount >= 2 {
                    return true
                }
            } else if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index -= 1
                continue
            } else {
                return false
            }
            index -= 1
        }
        return false
    }

    private static func annotatedSegments(
        from document: ReaderPageDocument,
        settings: ReaderAppearanceSettings
    ) -> [NovelAnnotatedSegment] {
        var results: [NovelAnnotatedSegment] = []
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
                NovelAnnotatedSegment(
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
        for annotatedSegment: NovelAnnotatedSegment,
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

    static func textFits(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> Bool {
#if canImport(UIKit)
        ReaderPagedLayoutEngine.textFits(
            text,
            chapterTitle: chapterTitle,
            settings: settings,
            layout: layout
        )
#elseif canImport(AppKit)
        AppKitNovelTextLayoutAdapter.textFits(
            text,
            chapterTitle: chapterTitle,
            settings: settings,
            layout: layout
        )
#else
        false
#endif
    }

    public static func measuredTextHeight(
        displayValue: NovelTextDisplayValue,
        width: CGFloat,
        baseFontSize: Double = 22
    ) throws -> CGFloat {
        try measuredTextHeight(
            displayValue.text,
            chapterTitle: displayValue.chapterTitle,
            startsAtParagraphBoundary: displayValue.startsAtParagraphBoundary,
            settings: ReaderAppearanceSettings(displaySemantics: displayValue.semantics),
            width: width,
            baseFontSize: baseFontSize
        )
    }

    public static func measuredTextHeight(
        _ text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings,
        width: CGFloat,
        baseFontSize: Double = 22
    ) throws -> CGFloat {
        guard width > 0 else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
#if canImport(UIKit)
        let height = ReaderPagedLayoutEngine.measuredTextHeight(
            text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            width: width,
            baseFontSize: baseFontSize
        )
#elseif canImport(AppKit)
        let height = AppKitNovelTextLayoutAdapter.measuredTextHeight(
            text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            width: width,
            baseFontSize: baseFontSize
        )
#else
        throw NovelTextLayoutFailure.unableToLayoutText
#endif
        guard height > 0, height.isFinite else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        return height
    }

    private static func pagedTextSlices(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        requiresAuthoritativeLayout: Bool,
        pagedLayout: NovelPagedTextLayout?
    ) throws -> [TextSlice] {
#if canImport(UIKit)
        let authoritativeLayout = pagedLayout ?? ReaderPagedLayoutEngine.paginateText
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#elseif canImport(AppKit)
        let authoritativeLayout = pagedLayout ?? AppKitNovelTextLayoutAdapter.paginateText
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#else
        if let pagedLayout {
            let slices = pagedLayout(text, chapterTitle, settings, layout)
            if !slices.isEmpty {
                return slices
            }
        }
#endif
        throw NovelTextLayoutFailure.unableToLayoutText
    }

    private static func verticalTextChunks(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        requiresAuthoritativeLayout: Bool,
        verticalLayout: NovelVerticalTextLayout?
    ) throws -> [TextSlice] {
#if canImport(UIKit)
        let authoritativeLayout = verticalLayout ?? ReaderPagedLayoutEngine.verticalTextChunks
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#elseif canImport(AppKit)
        let authoritativeLayout = verticalLayout ?? AppKitNovelTextLayoutAdapter.verticalTextChunks
        let slices = authoritativeLayout(
            text,
            chapterTitle,
            settings,
            layout
        )
        if !slices.isEmpty {
            return slices
        }
#else
        if let verticalLayout {
            let slices = verticalLayout(text, chapterTitle, settings, layout)
            if !slices.isEmpty {
                return slices
            }
        }
#endif
        throw NovelTextLayoutFailure.unableToLayoutText
    }

}

private extension ReaderAppearanceSettings {
    init(displaySemantics: NovelTextDisplaySemantics) {
        self.init(
            fontScale: displaySemantics.fontScale,
            fontFamily: displaySemantics.fontFamily,
            lineHeightScale: displaySemantics.lineHeightScale,
            characterSpacingScale: displaySemantics.characterSpacingScale,
            usesJustifiedText: displaySemantics.usesJustifiedText,
            indentsParagraphFirstLine: displaySemantics.indentsParagraphFirstLine
        )
    }
}

#if canImport(AppKit) && !canImport(UIKit)
private enum AppKitNovelTextLayoutAdapter {
    private static let defaultBaseFontSize: Double = 22

    static func textFits(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> Bool {
        let pageSize = layout.readableFrame.size
        guard pageSize.width >= 120, pageSize.height >= minimumUsablePageHeight(settings: settings) else {
            return false
        }

        let height = measuredTextHeight(
            text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: true,
            settings: settings,
            width: pageSize.width,
            baseFontSize: defaultBaseFontSize
        )
        return height > 0 && height <= pageSize.height
    }

    static func measuredTextHeight(
        _ text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool,
        settings: ReaderAppearanceSettings,
        width: CGFloat,
        baseFontSize: Double
    ) -> CGFloat {
        let attributedText = makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            startsAtParagraphBoundary: startsAtParagraphBoundary,
            settings: settings,
            baseFontSize: baseFontSize
        )
        guard width > 0, attributedText.length > 0 else { return 0 }
        return measuredTextHeightWithTextKit2(attributedText, width: width)
    }

    static func paginateText(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [TextSlice] {
        let pageSize = layout.readableFrame.size
        guard pageSize.width > 0, pageSize.height > 0 else {
            return []
        }
        guard pageSize.width >= 120, pageSize.height >= minimumUsablePageHeight(settings: settings) else {
            return []
        }

        let attributedText = makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        return paginateTextWithTextKit2(attributedText, pageSize: pageSize)
    }

    private static func measuredTextHeightWithTextKit2(_ attributedText: NSAttributedString, width: CGFloat) -> CGFloat {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textContentStorage.textStorage?.setAttributedString(attributedText)

        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        textLayoutManager.textContainer = textContainer

        textLayoutManager.ensureLayout(for: textContentStorage.documentRange)

        var maxY: CGFloat = 0
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentStorage.documentRange.location,
            options: []
        ) { fragment in
            maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
            return true
        }
        return ceil(maxY)
    }

    static func verticalTextChunks(
        _ text: String,
        chapterTitle: String?,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> [TextSlice] {
        let readableFrame = layout.readableFrame
        let chunkSize = CGSize(width: readableFrame.width, height: readableFrame.height * 1.8)
        guard chunkSize.width > 0, chunkSize.height > 0 else {
            return []
        }
        guard chunkSize.width >= 120, readableFrame.height >= minimumUsablePageHeight(settings: settings) else {
            return []
        }

        let attributedText = makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings
        )
        return paginateTextWithTextKit2(attributedText, pageSize: chunkSize)
    }

    static func makeAttributedText(
        text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings,
        baseFontSize: Double = defaultBaseFontSize,
        textColor: NSColor = .labelColor,
        titleWeight: NSFont.Weight = .regular
    ) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        let segments = ReaderChapterTextComponents.split(text: text, chapterTitle: chapterTitle)
        let pointSize = baseFontSize * settings.fontScale
        let firstBodyParagraphStyle = makeParagraphStyle(
            settings: settings,
            pointSize: pointSize,
            appliesFirstLineIndent: startsAtParagraphBoundary
        )
        let laterBodyParagraphStyle = makeParagraphStyle(
            settings: settings,
            pointSize: pointSize,
            appliesFirstLineIndent: true
        )
        let titleParagraphStyle = makeParagraphStyle(settings: settings, pointSize: pointSize, appliesFirstLineIndent: false)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.appKitFont(size: pointSize, weight: .regular),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: firstBodyParagraphStyle,
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.appKitFont(size: pointSize, weight: titleWeight),
            .kern: settings.fontFamily.kerning(size: pointSize, scale: settings.characterSpacingScale),
            .foregroundColor: textColor,
            .paragraphStyle: titleParagraphStyle,
        ]

        if let title = segments.title {
            rendered.append(NSAttributedString(string: title, attributes: titleAttributes))
            if let body = segments.body {
                appendBody(
                    body,
                    to: rendered,
                    attributes: bodyAttributes,
                    laterParagraphStyle: laterBodyParagraphStyle,
                    startsAtParagraphBoundary: startsAtParagraphBoundary
                )
            }
        } else {
            appendBody(
                text,
                to: rendered,
                attributes: bodyAttributes,
                laterParagraphStyle: laterBodyParagraphStyle,
                startsAtParagraphBoundary: startsAtParagraphBoundary
            )
        }

        return rendered
    }

    private static func paginateTextWithTextKit2(_ attributedText: NSAttributedString, pageSize: CGSize) -> [TextSlice] {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textContentStorage.textStorage?.setAttributedString(attributedText)

        let textContainer = NSTextContainer(size: CGSize(width: pageSize.width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        textLayoutManager.textContainer = textContainer

        let documentRange = textContentStorage.documentRange
        textLayoutManager.ensureLayout(for: documentRange)

        var pageRanges: [Int: NSRange] = [:]
        textLayoutManager.enumerateTextSegments(
            in: documentRange,
            type: .standard,
            options: []
        ) { textRange, rect, _, _ in
            guard let textRange,
                  let characterRange = nsRange(for: textRange, in: textContentStorage),
                  characterRange.length > 0,
                  rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite,
                  rect.height > 0 else {
                return true
            }
            let pageIndex = max(0, Int(floor(rect.midY / pageSize.height)))
            if let existingRange = pageRanges[pageIndex] {
                pageRanges[pageIndex] = existingRange.union(characterRange)
            } else {
                pageRanges[pageIndex] = characterRange
            }
            return true
        }

        if let lastPageIndex = pageRanges.keys.max(),
           let lastRange = pageRanges[lastPageIndex] {
            let textLength = attributedText.string.count
            let coveredEnd = min(lastRange.location + lastRange.length, textLength)
            if coveredEnd < textLength {
                pageRanges[lastPageIndex] = lastRange.union(
                    NSRange(location: coveredEnd, length: textLength - coveredEnd)
                )
            }
        }

        return pageRanges.keys.sorted().compactMap { pageIndex in
            guard let pageRange = pageRanges[pageIndex] else { return nil }
            return textSlice(
                from: attributedText,
                range: pageRange,
                isFirstPage: pageIndex == 0
            )
        }
    }

    private static func makeParagraphStyle(
        settings: ReaderAppearanceSettings,
        pointSize: Double,
        appliesFirstLineIndent: Bool
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6 * settings.lineHeightScale
        style.alignment = settings.usesJustifiedText ? .justified : .natural
        style.lineBreakMode = .byWordWrapping
        if settings.indentsParagraphFirstLine, appliesFirstLineIndent {
            style.firstLineHeadIndent = CGFloat(pointSize * 2)
        }
        return style
    }

    private static func appendBody(
        _ body: String,
        to rendered: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any],
        laterParagraphStyle: NSParagraphStyle,
        startsAtParagraphBoundary: Bool
    ) {
        let bodyStartLocation = rendered.length
        rendered.append(NSAttributedString(string: body, attributes: attributes))
        guard !startsAtParagraphBoundary else { return }

        for range in ReaderParagraphIndentPlanner.indentedParagraphRangesAfterFirst(in: body) {
            let location = body.distance(from: body.startIndex, to: range.lowerBound)
            let length = body.distance(from: range.lowerBound, to: range.upperBound)
            guard length > 0 else { continue }
            rendered.addAttribute(
                .paragraphStyle,
                value: laterParagraphStyle,
                range: NSRange(location: bodyStartLocation + location, length: length)
            )
        }
    }

    private static func nsRange(for textRange: NSTextRange, in contentManager: NSTextContentManager) -> NSRange? {
        let documentStart = contentManager.documentRange.location
        let start = contentManager.offset(from: documentStart, to: textRange.location)
        let end = contentManager.offset(from: documentStart, to: textRange.endLocation)
        guard start != NSNotFound, end != NSNotFound, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func textSlice(from attributedText: NSAttributedString, range: NSRange, isFirstPage: Bool) -> TextSlice? {
        let textLength = attributedText.string.count
        let pageCharacterStart = max(0, min(range.location, textLength))
        let nextCharacterEnd = min(range.location + range.length, textLength)
        let trimmedEnd = max(
            trimmedCharacterBoundary(in: attributedText.string, from: pageCharacterStart, to: nextCharacterEnd),
            pageCharacterStart
        )
        guard trimmedEnd > pageCharacterStart else { return nil }

        let candidateText = attributedText.attributedSubstring(
            from: NSRange(location: pageCharacterStart, length: trimmedEnd - pageCharacterStart)
        ).string
        guard !candidateText.isEmpty else { return nil }

        let trimmedLeadingText = candidateText.trimmingLeadingPaginationWhitespace()
        let leadingTrimmed = candidateText.count - trimmedLeadingText.count
        let effectiveStart = pageCharacterStart + leadingTrimmed
        let sliceText = effectiveStart < trimmedEnd ? attributedText.attributedSubstring(
            from: NSRange(location: effectiveStart, length: trimmedEnd - effectiveStart)
        ).string : ""
        guard !sliceText.isEmpty else { return nil }

        return TextSlice(
            text: sliceText,
            startOffset: effectiveStart,
            endOffset: trimmedEnd,
            startsAtParagraphBoundary: isFirstPage || isParagraphBoundary(in: attributedText.string, at: effectiveStart)
        )
    }

    private static func trimmedCharacterBoundary(in text: String, from start: Int, to candidateEnd: Int) -> Int {
        guard candidateEnd > start else { return start }
        let nsText = text as NSString
        var end = candidateEnd
        while end > start {
            let character = nsText.substring(with: NSRange(location: end - 1, length: 1))
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end -= 1
                continue
            }
            break
        }
        return max(end, start)
    }

    private static func minimumUsablePageHeight(settings: ReaderAppearanceSettings) -> CGFloat {
        let fontSize = max(14, defaultBaseFontSize * settings.fontScale)
        return CGFloat(fontSize * max(settings.lineHeightScale, 1.35) * 2)
    }

    private static func isParagraphBoundary(in text: String, at offset: Int) -> Bool {
        guard offset > 0, offset <= text.count else { return false }
        let nsText = text as NSString
        var index = offset - 1
        var newlineCount = 0

        while index >= 0 {
            let character = nsText.substring(with: NSRange(location: index, length: 1))
            if character == "\n" || character == "\r" {
                newlineCount += 1
                if newlineCount >= 2 {
                    return true
                }
            } else if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index -= 1
                continue
            } else {
                return false
            }
            index -= 1
        }

        return false
    }
}

private extension ReaderFontFamily {
    func appKitFont(size: Double, weight: NSFont.Weight) -> NSFont {
        let pointSize = CGFloat(size)
        switch self {
        case .systemSans:
            return preferredFamilyFont(familyName: "PingFang SC", size: pointSize, weight: weight)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        case .systemSerif:
            return preferredFamilyFont(familyName: "Songti SC", size: pointSize, weight: weight)
                ?? .systemFont(ofSize: pointSize, weight: weight)
        case .rounded:
            let descriptor = NSFont.systemFont(ofSize: pointSize, weight: weight).fontDescriptor
            let roundedDescriptor = descriptor.withDesign(.rounded) ?? descriptor
            return NSFont(descriptor: roundedDescriptor, size: pointSize) ?? .systemFont(ofSize: pointSize, weight: weight)
        }
    }

    func kerning(size: Double, scale: Double) -> CGFloat {
        CGFloat(size * scale * 0.55)
    }

    private func preferredFamilyFont(familyName: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let fontManager = NSFontManager.shared
        return fontManager.font(
            withFamily: familyName,
            traits: [],
            weight: fontManagerWeight(for: weight),
            size: size
        )
    }

    private func fontManagerWeight(for weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight: 2
        case .thin: 3
        case .light: 4
        case .regular: 5
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        case .heavy: 10
        case .black: 12
        default: 5
        }
    }
}

private extension String {
    func trimmingLeadingPaginationWhitespace() -> String {
        guard !isEmpty else { return self }
        var result = self[...]
        while let first = result.first, first.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            result.removeFirst()
        }
        return String(result)
    }
}
#endif

struct TextSlice {
    let text: String
    let startOffset: Int
    let endOffset: Int
    let startsAtParagraphBoundary: Bool

    init(
        text: String,
        startOffset: Int,
        endOffset: Int,
        startsAtParagraphBoundary: Bool = true
    ) {
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.startsAtParagraphBoundary = startsAtParagraphBoundary
    }
}

private struct NovelAnnotatedSegment {
    let index: Int
    let segment: ReaderSegment
    let chapterOrdinal: Int?
    let chapterTitle: String?

    var textContent: String {
        guard case let .text(text, _) = segment else { return "" }
        return text
    }
}

private struct NovelViewportPageDraft {
    let orderSegmentIndex: Int
    let ordinal: Int
    let kind: NovelViewportPageDraftKind
}

private enum NovelViewportPageDraftKind {
    case text([ReaderRenderedTextRange])
    case image(url: URL, chapterTitle: String?, externalBlock: NovelTextViewportExternalBlock)
}

private struct NovelTextViewportIndexCacheKey: Hashable {
    var document: ReaderPageDocument
    var settings: ReaderAppearanceSettings
    var layout: ReaderContainerLayout
}

private final class NovelTextViewportIndexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [NovelTextViewportIndexCacheKey: NovelTextLayoutResult] = [:]
    private var accessOrder: [NovelTextViewportIndexCacheKey] = []
    private let capacity = 16

    func result(for key: NovelTextViewportIndexCacheKey) -> NovelTextLayoutResult? {
        lock.withLock {
            guard let result = entries[key] else { return nil }
            markRecentlyUsed(key)
            return result
        }
    }

    func store(_ result: NovelTextLayoutResult, for key: NovelTextViewportIndexCacheKey) {
        lock.withLock {
            entries[key] = result
            markRecentlyUsed(key)
            trimIfNeeded()
        }
    }

    private func markRecentlyUsed(_ key: NovelTextViewportIndexCacheKey) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func trimIfNeeded() {
        while accessOrder.count > capacity, let oldestKey = accessOrder.first {
            accessOrder.removeFirst()
            entries.removeValue(forKey: oldestKey)
        }
    }
}
