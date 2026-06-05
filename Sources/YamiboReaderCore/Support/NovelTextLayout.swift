import CoreGraphics
import Foundation

typealias NovelTextViewportPageLayout = @Sendable (
    _ viewportContext: NovelTextViewportContext,
    _ settings: ReaderAppearanceSettings,
    _ layout: ReaderContainerLayout
) -> [NovelTextViewportDocumentPageRange]

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
) throws -> NovelTextLayoutResult

public enum NovelTextLayout {
    private static let viewportIndexCache = NovelTextViewportIndexCache()

    static func displayValue(
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
        try makeViewport(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: nil
        )
    }

    public static func layout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        try makeViewport(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: nil
        )
    }

    public static func makeViewport(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        try makeViewport(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: nil
        )
    }

    public static func updateViewport(
        _ viewport: NovelTextLayoutResult,
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> NovelTextLayoutResult {
        _ = viewport
        return try makeViewport(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: nil
        )
    }

    static func viewportSample(
        displayOffset: Int,
        displayValue: NovelTextDisplayValue,
        documentView: Int,
        pageIndex: Int
    ) -> NovelTextViewportSample? {
        guard !displayValue.ranges.isEmpty else { return nil }
        let normalizedOffset = max(0, displayOffset)
        var runningOffset = 0

        for range in displayValue.ranges {
            let length = max(range.length, 0)
            let rangeEnd = runningOffset + length
            if normalizedOffset <= rangeEnd {
                return NovelTextViewportSample(
                    documentView: documentView,
                    pageIndex: pageIndex,
                    segmentIndex: range.segmentIndex,
                    segmentOffset: range.startOffset + min(max(normalizedOffset - runningOffset, 0), length)
                )
            }
            runningOffset = rangeEnd + 2
        }

        guard let lastRange = displayValue.ranges.last else { return nil }
        return NovelTextViewportSample(
            documentView: documentView,
            pageIndex: pageIndex,
            segmentIndex: lastRange.segmentIndex,
            segmentOffset: lastRange.endOffset
        )
    }

    static func displayOffset(
        forSegmentIndex segmentIndex: Int,
        segmentOffset: Int,
        displayValue: NovelTextDisplayValue
    ) -> Int? {
        var runningOffset = 0

        for range in displayValue.ranges {
            let length = max(range.length, 0)
            defer { runningOffset += length + 2 }
            guard range.segmentIndex == segmentIndex,
                  segmentOffset >= range.startOffset,
                  segmentOffset <= range.endOffset else {
                continue
            }
            return runningOffset + min(max(segmentOffset - range.startOffset, 0), length)
        }

        return nil
    }

    static func renderedPages(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        viewportPageLayout: NovelTextViewportPageLayout? = nil,
        usesViewportIndexCache: Bool? = nil
    ) throws -> NovelTextLayoutResult {
        try makeViewport(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: viewportPageLayout,
            usesViewportIndexCache: usesViewportIndexCache
        )
    }

    static func layout(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        viewportPageLayout: NovelTextViewportPageLayout? = nil,
        usesViewportIndexCache: Bool? = nil
    ) throws -> NovelTextLayoutResult {
        try makeViewport(
            document: document,
            settings: settings,
            layout: layout,
            viewportPageLayout: viewportPageLayout,
            usesViewportIndexCache: usesViewportIndexCache
        )
    }

    static func makeViewport(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        viewportPageLayout: NovelTextViewportPageLayout? = nil,
        usesViewportIndexCache: Bool? = nil
    ) throws -> NovelTextLayoutResult {
        let cacheKey = NovelTextViewportIndexCacheKey(
            document: document,
            settings: settings,
            layout: layout
        )
        let shouldUseCache = usesViewportIndexCache ?? (viewportPageLayout == nil)
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
            viewportPageLayout: { viewportContext, settings, layout in
                if let viewportPageLayout {
                    return viewportPageLayout(viewportContext, settings, layout)
                }
                return try viewportDocumentPageRanges(
                    viewportContext: viewportContext,
                    settings: settings,
                    layout: layout
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

    static func viewportDocumentPageRanges(
        viewportContext: NovelTextViewportContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> [NovelTextViewportDocumentPageRange] {
        switch settings.readingMode {
        case .paged:
            return try pagedViewportDocumentRanges(
                viewportContext: viewportContext,
                settings: settings,
                layout: layout
            )
        case .vertical:
            return try verticalViewportDocumentRanges(
                viewportContext: viewportContext,
                settings: settings,
                layout: layout
            )
        }
    }

    private static func render(
        annotatedSegments: [NovelAnnotatedSegment],
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        viewportContextSeed: NovelTextViewportContext,
        viewportPageLayout: (NovelTextViewportContext, ReaderAppearanceSettings, ReaderContainerLayout) throws -> [NovelTextViewportDocumentPageRange]
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
            let pageRanges = try viewportPageLayout(viewportContextSeed, settings, layout)
            for pageRange in pageRanges where !pageRange.isEmpty {
                let ranges = segmentRanges(
                    for: pageRange,
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
                            kind: .text(group, frozenGeometry: pageRange.frozenGeometry)
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
                    frozenFrame: frozenExternalBlockFrame(layout: layout),
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
            case let .text(ranges, frozenGeometry):
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
                    frozenGeometry: frozenGeometry,
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
            viewportIndex: viewportIndex,
            layoutMetrics: layoutMetrics(
                viewportContext: viewportContext,
                viewportIndex: viewportIndex,
                settings: settings,
                layout: layout
            )
        )
    }

    private static func layoutMetrics(
        viewportContext: NovelTextViewportContext,
        viewportIndex: NovelTextViewportIndex,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) -> NovelTextViewportLayoutMetrics {
        let contentWidth = max(layout.readableFrame.width, 1)
        let pageMetrics = Dictionary(
            uniqueKeysWithValues: viewportIndex.pages.map { page in
                let textHeight = page.frozenGeometry?.contentHeight ?? (try? displayValue(
                    viewportContext: viewportContext,
                    viewportPage: page,
                    settings: settings
                ).heightForViewportMetrics(width: contentWidth))
                let externalBlockHeight = CGFloat(page.externalBlocks.count) *
                    min(max(contentWidth * 0.65, 160), max(layout.readableFrame.height, 160))
                let blockCount = (textHeight == nil ? 0 : 1) + page.externalBlocks.count
                let spacingHeight = CGFloat(max(blockCount - 1, 0)) * 14
                return (
                    page.pageIndex,
                    NovelTextViewportPageLayoutMetrics(
                        pageIndex: page.pageIndex,
                        textHeight: textHeight,
                        externalBlockHeight: externalBlockHeight,
                        spacingHeight: spacingHeight
                    )
                )
            }
        )
        return NovelTextViewportLayoutMetrics(pageMetrics: pageMetrics)
    }

    private static func frozenExternalBlockFrame(layout: ReaderContainerLayout) -> NovelTextViewportExternalBlockFrame {
        let contentWidth = max(layout.readableFrame.width, 1)
        let height = min(max(contentWidth * 0.65, 160), max(layout.readableFrame.height, 160))
        return NovelTextViewportExternalBlockFrame(
            x: 0,
            y: 0,
            width: contentWidth,
            height: height
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
        for pageRange: NovelTextViewportDocumentPageRange,
        viewportDocument: NovelTextViewportDocument
    ) -> [ReaderRenderedTextRange] {
        let sliceStart = max(0, pageRange.startOffset)
        let sliceEnd = max(sliceStart, pageRange.endOffset)
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
#else
        false
#endif
    }

    static func measuredTextHeight(
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

    @_spi(NovelTextLayoutMeasurement)
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
        guard height > 0, height.isFinite else {
            throw NovelTextLayoutFailure.unableToLayoutText
        }
        return height
#else
        throw NovelTextLayoutFailure.unableToLayoutText
#endif
    }

    private static func pagedViewportDocumentRanges(
        viewportContext: NovelTextViewportContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> [NovelTextViewportDocumentPageRange] {
#if canImport(UIKit)
        let ranges = ReaderPagedLayoutEngine.paginateViewportDocument(
            viewportContext.document.text,
            settings: settings,
            layout: layout
        )
        if !ranges.isEmpty {
            return ranges
        }
#else
        let ranges = pureValueViewportDocumentRanges(
            viewportContext: viewportContext,
            layout: layout
        )
        if !ranges.isEmpty {
            return ranges
        }
#endif
        throw NovelTextLayoutFailure.unableToLayoutText
    }

    private static func verticalViewportDocumentRanges(
        viewportContext: NovelTextViewportContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) throws -> [NovelTextViewportDocumentPageRange] {
#if canImport(UIKit)
        let ranges = ReaderPagedLayoutEngine.verticalViewportDocumentChunks(
            viewportContext.document.text,
            settings: settings,
            layout: layout
        )
        if !ranges.isEmpty {
            return ranges
        }
#else
        let ranges = pureValueViewportDocumentRanges(
            viewportContext: viewportContext,
            layout: layout
        )
        if !ranges.isEmpty {
            return ranges
        }
#endif
        throw NovelTextLayoutFailure.unableToLayoutText
    }

    private static func pureValueViewportDocumentRanges(
        viewportContext: NovelTextViewportContext,
        layout: ReaderContainerLayout
    ) -> [NovelTextViewportDocumentPageRange] {
        let readableHeight = max(layout.readableFrame.height, 1)
        let chunkLength = max(1, Int(readableHeight / 4))
        return viewportContext.document.textRangesBySegment
            .values
            .sorted { $0.startOffset < $1.startOffset }
            .flatMap { range -> [NovelTextViewportDocumentPageRange] in
                guard range.endOffset > range.startOffset else { return [] }
                return stride(from: range.startOffset, to: range.endOffset, by: chunkLength).map { start in
                    NovelTextViewportDocumentPageRange(
                        startOffset: start,
                        endOffset: min(start + chunkLength, range.endOffset)
                    )
                }
            }
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

private extension NovelTextDisplayValue {
    func heightForViewportMetrics(width: CGFloat) throws -> CGFloat {
        try NovelTextLayout.measuredTextHeight(displayValue: self, width: width)
    }
}


struct NovelTextViewportDocumentPageRange: Hashable, Sendable {
    let startOffset: Int
    let endOffset: Int
    let frozenGeometry: NovelTextViewportFrozenGeometry?

    var isEmpty: Bool {
        endOffset <= startOffset
    }

    init(
        startOffset: Int,
        endOffset: Int,
        frozenGeometry: NovelTextViewportFrozenGeometry? = nil
    ) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.frozenGeometry = frozenGeometry
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
    case text([ReaderRenderedTextRange], frozenGeometry: NovelTextViewportFrozenGeometry?)
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
