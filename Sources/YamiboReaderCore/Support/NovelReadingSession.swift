import Foundation

public struct ReaderPagedSpread: Identifiable, Equatable, Sendable {
    public let index: Int
    public let leftPageIndex: Int
    public let rightPageIndex: Int?
    public let chapterTitle: String?

    public var id: Int { index }

    public init(index: Int, leftPageIndex: Int, rightPageIndex: Int?, chapterTitle: String?) {
        self.index = max(0, index)
        self.leftPageIndex = max(0, leftPageIndex)
        self.rightPageIndex = rightPageIndex
        self.chapterTitle = chapterTitle
    }
}

public struct NovelReadingSnapshot: Equatable, Sendable {
    public var pages: [NovelTextViewportIndexPage]
    public var chapters: [ReaderChapter]
    public var currentPageIndex: Int
    public var currentPageIntraProgress: Double
    public var currentView: Int
    public var maxView: Int
    public var currentChapterTitle: String?
    public var currentContentSource: ReaderContentSource
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int
    public var pagedSpreads: [ReaderPagedSpread]
    public var prefetchedStartIndex: Int?
    public var currentAuthorID: String?
    public var viewportContext: NovelTextViewportContext?
    public var viewportIndex: NovelTextViewportIndex?

    public init(
        pages: [NovelTextViewportIndexPage],
        chapters: [ReaderChapter],
        currentPageIndex: Int,
        currentPageIntraProgress: Double,
        currentView: Int,
        maxView: Int,
        currentChapterTitle: String?,
        currentContentSource: ReaderContentSource,
        retainedChapterCount: Int,
        filteredChapterCandidateCount: Int,
        pagedSpreads: [ReaderPagedSpread],
        prefetchedStartIndex: Int?,
        currentAuthorID: String?,
        viewportContext: NovelTextViewportContext? = nil,
        viewportIndex: NovelTextViewportIndex? = nil
    ) {
        self.pages = pages
        self.chapters = chapters
        self.currentPageIndex = max(0, currentPageIndex)
        self.currentPageIntraProgress = min(max(currentPageIntraProgress, 0), 1)
        self.currentView = max(1, currentView)
        self.maxView = max(self.currentView, maxView)
        self.currentChapterTitle = currentChapterTitle
        self.currentContentSource = currentContentSource
        self.retainedChapterCount = max(0, retainedChapterCount)
        self.filteredChapterCandidateCount = max(0, filteredChapterCandidateCount)
        self.pagedSpreads = pagedSpreads
        self.prefetchedStartIndex = prefetchedStartIndex
        self.currentAuthorID = currentAuthorID
        self.viewportContext = viewportContext
        self.viewportIndex = viewportIndex
    }
}

public enum NovelReadingNavigationRequest: Equatable, Sendable {
    case loadView(view: Int, preferredPage: Int, resumePoint: ReaderResumePoint?)
    case promotePrefetched(preferredPage: Int, resumePoint: ReaderResumePoint?)
}

public struct NovelReadingSession: Sendable {
    public private(set) var snapshot: NovelReadingSnapshot

    private var settings: ReaderAppearanceSettings
    private var layout: ReaderContainerLayout
    private var currentDocument: ReaderPageDocument
    private var prefetchedDocument: ReaderPageDocument?
    private var usesPadPresentation: Bool
    private var pendingResumePoint: ReaderResumePoint?
    private var pendingResumeRequiresLayoutSync = false
    private var currentViewportIndex: NovelTextViewportIndex?
    private var preservedTextResumePoint: ReaderResumePoint?
    private let pagination: NovelTextPagination

    init(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        preferredPage: Int = 0,
        resumePoint: ReaderResumePoint? = nil,
        usesPadPresentation: Bool = false,
        currentAuthorID: String? = nil
    ) {
        self.init(
            unpaginatedDocument: document,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation,
            currentAuthorID: currentAuthorID,
            pagination: NovelTextLayout.layout
        )
        preservedTextResumePoint = resumePoint
        applyPaginationIgnoringFailure(for: document, preferredPage: preferredPage, preferredResumePoint: resumePoint)
    }

    public init(
        validating document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        preferredPage: Int = 0,
        resumePoint: ReaderResumePoint? = nil,
        usesPadPresentation: Bool = false,
        currentAuthorID: String? = nil,
        pagination: @escaping NovelTextPagination = NovelTextLayout.layout
    ) throws {
        self.init(
            unpaginatedDocument: document,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation,
            currentAuthorID: currentAuthorID,
            pagination: pagination
        )
        preservedTextResumePoint = resumePoint
        try applyPagination(for: document, preferredPage: preferredPage, preferredResumePoint: resumePoint)
    }

    private init(
        unpaginatedDocument document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool,
        currentAuthorID: String?,
        pagination: @escaping NovelTextPagination
    ) {
        self.settings = settings
        self.layout = layout
        self.currentDocument = document
        self.usesPadPresentation = usesPadPresentation
        self.pendingResumePoint = nil
        self.currentViewportIndex = nil
        self.preservedTextResumePoint = nil
        self.pagination = pagination
        self.snapshot = NovelReadingSnapshot(
            pages: [],
            chapters: [],
            currentPageIndex: 0,
            currentPageIntraProgress: 0,
            currentView: document.view,
            maxView: document.maxView,
            currentChapterTitle: nil,
            currentContentSource: document.contentSource,
            retainedChapterCount: document.retainedChapterCount,
            filteredChapterCandidateCount: document.filteredChapterCandidateCount,
            pagedSpreads: [],
            prefetchedStartIndex: nil,
            currentAuthorID: document.resolvedAuthorID ?? currentAuthorID,
            viewportContext: nil,
            viewportIndex: nil
        )
    }

    private var isTwoPageSpreadActive: Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            layout.width > layout.height
    }

    public mutating func applySettings(_ newSettings: ReaderAppearanceSettings) throws {
        let oldSettings = settings
        let oldPendingResumePoint = pendingResumePoint
        let oldPendingResumeRequiresLayoutSync = pendingResumeRequiresLayoutSync
        let shouldRepaginate = oldSettings != newSettings
        let resumePoint = shouldRepaginate ? captureNovelReadingPosition() : nil
        if shouldRepaginate {
            pendingResumePoint = resumePoint
            pendingResumeRequiresLayoutSync = oldSettings.readingMode != newSettings.readingMode
        }
        settings = newSettings
        guard shouldRepaginate else { return }
        do {
            try applyPagination(for: currentDocument, preferredPage: snapshot.currentPageIndex, preferredResumePoint: resumePoint)
        } catch {
            settings = oldSettings
            pendingResumePoint = oldPendingResumePoint
            pendingResumeRequiresLayoutSync = oldPendingResumeRequiresLayoutSync
            throw error
        }
        clearPendingResumePointIfSettled()
    }

    public mutating func updateLayout(_ layout: ReaderContainerLayout) throws {
        guard self.layout != layout else { return }
        let resumePoint = pendingResumePoint ?? captureNovelReadingPosition()
        let oldLayout = self.layout
        self.layout = layout
        do {
            try applyPagination(for: currentDocument, preferredPage: snapshot.currentPageIndex, preferredResumePoint: resumePoint)
        } catch {
            self.layout = oldLayout
            throw error
        }
        clearPendingResumePointIfSettled()
    }

    public mutating func updatePagedPresentationEnvironment(isPad: Bool) throws {
        guard usesPadPresentation != isPad else { return }
        let oldUsesPadPresentation = usesPadPresentation
        usesPadPresentation = isPad
        guard settings.readingMode == .paged else { return }
        do {
            try applyPagination(
                for: currentDocument,
                preferredPage: snapshot.currentPageIndex,
                preferredResumePoint: captureNovelReadingPosition()
            )
        } catch {
            usesPadPresentation = oldUsesPadPresentation
            throw error
        }
    }

    public mutating func jumpToRenderedPage(_ pageIndex: Int) {
        updateLocation(pageIndex: pageIndex, intraPageProgress: 0)
    }

    @discardableResult
    public mutating func jumpRelativePage(_ delta: Int) -> NovelReadingNavigationRequest? {
        guard delta != 0 else { return nil }

        if settings.readingMode == .paged, isTwoPageSpreadActive {
            let targetSpreadIndex = spreadIndex(
                forPageIndex: snapshot.currentPageIndex,
                pages: snapshot.pages,
                pagedSpreads: snapshot.pagedSpreads
            ) + delta
            if targetSpreadIndex >= 0, targetSpreadIndex < snapshot.pagedSpreads.count {
                jumpToRenderedPage(leftPageIndex(forSpreadIndex: targetSpreadIndex, pagedSpreads: snapshot.pagedSpreads))
                return nil
            }
        }

        let targetIndex = snapshot.currentPageIndex + delta
        if targetIndex >= 0, targetIndex < snapshot.pages.count {
            jumpToRenderedPage(targetIndex)
            return nil
        }

        if targetIndex < 0 {
            let previousView = max(snapshot.currentView - 1, 1)
            guard previousView < snapshot.currentView else {
                jumpToRenderedPage(0)
                return nil
            }
            return .loadView(view: previousView, preferredPage: .max, resumePoint: nil)
        }

        if prefetchedDocument?.view == snapshot.currentView + 1 {
            return .promotePrefetched(preferredPage: 0, resumePoint: nil)
        }

        let nextView = min(snapshot.currentView + 1, snapshot.maxView)
        guard nextView > snapshot.currentView else {
            jumpToRenderedPage(max(snapshot.pages.count - 1, 0))
            return nil
        }
        return .loadView(view: nextView, preferredPage: 0, resumePoint: nil)
    }

    public mutating func updateVerticalViewportPosition(pageIndex: Int, intraPageProgress: Double) {
        updateLocation(pageIndex: pageIndex, intraPageProgress: intraPageProgress)
        preserveCurrentTextResumePointIfAvailable()
    }

    public mutating func updateVerticalViewportPosition(sample: NovelTextViewportSample) {
        guard settings.readingMode == .vertical,
              let target = resolveViewportSample(sample) else {
            updateVerticalViewportPosition(
                pageIndex: sample.pageIndex,
                intraPageProgress: 0
            )
            return
        }
        setCurrentLocation(target)
        preserveCurrentTextResumePointIfAvailable()
    }

    public mutating func acceptPrefetchedDocument(_ document: ReaderPageDocument) {
        prefetchedDocument = document
        snapshot.maxView = max(snapshot.maxView, document.maxView)
    }

    public mutating func promotePrefetchedDocument(
        preferredPage: Int = 0,
        resumePoint: ReaderResumePoint? = nil
    ) throws {
        guard let nextDocument = prefetchedDocument else { return }
        let previousDocument = currentDocument
        let previousPrefetchedDocument = prefetchedDocument
        currentDocument = nextDocument
        prefetchedDocument = nil
        let effectiveResumePoint = resumePoint?.view == nextDocument.view ? resumePoint : nil
        do {
            try applyPagination(for: nextDocument, preferredPage: preferredPage, preferredResumePoint: effectiveResumePoint)
        } catch {
            currentDocument = previousDocument
            prefetchedDocument = previousPrefetchedDocument
            throw error
        }
    }

    public func captureNovelReadingPosition() -> ReaderResumePoint? {
        currentNovelReadingPosition() ?? preservedTextResumePoint
    }

    private func currentNovelReadingPosition() -> ReaderResumePoint? {
        guard let page = currentRenderedPage,
              let chapterOrdinal = page.chapterOrdinal,
              let position = textPosition(for: snapshot.currentPageIntraProgress, in: page) else {
            return nil
        }

        let range = position.range
        let segmentLength = range.length
        let offsetWithinSegment = segmentLength > 0
            ? Int((Double(segmentLength) * position.progressInRange).rounded(.towardZero))
            : 0
        return ReaderResumePoint(
            view: page.documentView,
            chapterOrdinal: chapterOrdinal,
            chapterTitle: page.chapterTitle,
            segmentIndex: range.segmentIndex,
            segmentOffset: range.startOffset + min(offsetWithinSegment, segmentLength),
            segmentProgress: snapshot.currentPageIntraProgress,
            authorID: snapshot.currentAuthorID,
            readingModeHint: settings.readingMode
        )
    }

    public func currentPreviewSourceText() -> String {
        guard let page = currentRenderedPage,
              let document = document(for: page.documentView),
              !document.segments.isEmpty else {
            return ""
        }

        guard let currentPosition = textPosition(for: snapshot.currentPageIntraProgress, in: page) else {
            return ""
        }
        let startSegmentIndex = min(
            max(currentPosition.range.segmentIndex, 0),
            max(document.segments.count - 1, 0)
        )
        let startOffset = sourceOffset(for: currentPosition)

        let fragments = document.segments[startSegmentIndex...].enumerated().compactMap { offset, segment -> String? in
            guard case let .text(text, _) = segment else { return nil }

            let previewText = offset == 0
                ? text.droppingReaderPreviewCharacters(startOffset)
                : text
            let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return fragments.joined(separator: "\n\n")
    }

    private func sourceOffset(for position: ReaderPageTextPosition) -> Int {
        let range = position.range
        let segmentLength = range.length
        let offsetWithinSegment = segmentLength > 0
            ? Int((Double(segmentLength) * position.progressInRange).rounded(.towardZero))
            : 0
        return range.startOffset + min(offsetWithinSegment, segmentLength)
    }

    private var effectivePaginationLayout: ReaderContainerLayout {
        guard isTwoPageSpreadActive else { return layout }

        return ReaderContainerLayout(
            containerSize: CGSize(width: layout.width / 2, height: layout.height),
            safeAreaInsets: ReaderLayoutInsets(
                top: layout.safeAreaInsets.top,
                bottom: layout.safeAreaInsets.bottom
            ),
            contentInsets: layout.contentInsets,
            chromeInsets: layout.chromeInsets,
            readingMode: layout.readingMode
        )
    }

    private func chapterTitle(for pageIndex: Int, pages: [NovelTextViewportIndexPage], chapters: [ReaderChapter]) -> String? {
        guard pages.indices.contains(pageIndex) else {
            return chapters.last(where: { $0.startIndex <= pageIndex })?.title
        }
        return pages[pageIndex].chapterTitle ?? chapters.last(where: { $0.startIndex <= pageIndex })?.title
    }

    private var currentRenderedPage: NovelTextViewportIndexPage? {
        let normalizedIndex = normalizedPagedPageIndex(
            snapshot.currentPageIndex,
            pages: snapshot.pages,
            pagedSpreads: snapshot.pagedSpreads
        )
        guard snapshot.pages.indices.contains(normalizedIndex) else { return nil }
        return snapshot.pages[normalizedIndex]
    }

    private func document(for view: Int) -> ReaderPageDocument? {
        if view == prefetchedDocument?.view {
            return prefetchedDocument
        }
        if view == currentDocument.view {
            return currentDocument
        }
        return nil
    }

    private mutating func updateLocation(pageIndex: Int, intraPageProgress: Double) {
        let normalizedPageIndex = normalizedPagedPageIndex(
            pageIndex,
            pages: snapshot.pages,
            pagedSpreads: snapshot.pagedSpreads
        )
        let target = ReaderResolvedTarget(
            pageIndex: normalizedPageIndex,
            intraPageProgress: intraPageProgress,
            documentView: displayedViewCandidate(for: normalizedPageIndex, pages: snapshot.pages)
        )
        setCurrentLocation(target)
    }

    private mutating func setCurrentLocation(_ target: ReaderResolvedTarget) {
        let normalizedPageIndex = normalizedPagedPageIndex(
            target.pageIndex,
            pages: snapshot.pages,
            pagedSpreads: snapshot.pagedSpreads
        )
        snapshot.currentPageIndex = normalizedPageIndex
        snapshot.currentPageIntraProgress = min(max(target.intraPageProgress, 0), 1)
        snapshot.currentChapterTitle = chapterTitle(
            for: normalizedPageIndex,
            pages: snapshot.pages,
            chapters: snapshot.chapters
        )
    }

    private mutating func clearPendingResumePointIfSettled() {
        guard pendingResumePoint != nil else { return }
        guard !pendingResumeRequiresLayoutSync || layout.readingMode == settings.readingMode else { return }
        pendingResumePoint = nil
        pendingResumeRequiresLayoutSync = false
    }

    private mutating func applyPagination(
        for document: ReaderPageDocument,
        preferredPage: Int,
        preferredResumePoint: ReaderResumePoint?
    ) throws {
        let paginationLayout = effectivePaginationLayout
        let layoutResult = try pagination(document, settings, paginationLayout)
        let viewportPages = layoutResult.viewportIndex.pages
        let renderedChapters = Self.readerChapters(from: layoutResult.viewportIndex)
        let prefetchedStartIndex: Int? = nil

        let pages = viewportPages
        let fallbackTarget = ReaderResolvedTarget(
            pageIndex: max(0, min(preferredPage, max(pages.count - 1, 0))),
            intraPageProgress: 0,
            documentView: displayedViewCandidate(for: preferredPage, pages: pages)
        )
        let effectiveResumePoint = pendingResumePoint ?? preferredResumePoint
        currentViewportIndex = layoutResult.viewportIndex
        let resolvedTarget = effectiveResumePoint.flatMap { resolveResumePoint($0, in: pages) } ?? fallbackTarget
        let normalizedPageIndex = normalizedPagedPageIndex(resolvedTarget.pageIndex, pages: pages, pagedSpreads: makePagedSpreads(from: pages))
        snapshot = NovelReadingSnapshot(
            pages: pages,
            chapters: renderedChapters,
            currentPageIndex: normalizedPageIndex,
            currentPageIntraProgress: resolvedTarget.intraPageProgress,
            currentView: document.view,
            maxView: document.maxView,
            currentChapterTitle: chapterTitle(for: normalizedPageIndex, pages: pages, chapters: renderedChapters),
            currentContentSource: document.contentSource,
            retainedChapterCount: document.retainedChapterCount,
            filteredChapterCandidateCount: document.filteredChapterCandidateCount,
            pagedSpreads: makePagedSpreads(from: pages),
            prefetchedStartIndex: prefetchedStartIndex,
            currentAuthorID: document.resolvedAuthorID ?? snapshot.currentAuthorID,
            viewportContext: layoutResult.viewportContext,
            viewportIndex: layoutResult.viewportIndex
        )
        preserveCurrentTextResumePointIfAvailable()
    }

    private mutating func preserveCurrentTextResumePointIfAvailable() {
        guard let resumePoint = currentNovelReadingPosition() else { return }
        preservedTextResumePoint = resumePoint
    }

    private static func readerChapters(from viewportIndex: NovelTextViewportIndex) -> [ReaderChapter] {
        viewportIndex.chapters.map { chapter in
            ReaderChapter(
                ordinal: chapter.ordinal,
                title: chapter.title,
                startIndex: chapter.startPageIndex,
                chapterCommentTarget: chapter.chapterCommentTarget
            )
        }
    }

    private mutating func applyPaginationIgnoringFailure(
        for document: ReaderPageDocument,
        preferredPage: Int,
        preferredResumePoint: ReaderResumePoint?
    ) {
        try? applyPagination(
            for: document,
            preferredPage: preferredPage,
            preferredResumePoint: preferredResumePoint
        )
    }

    private func displayedViewCandidate(for preferredPage: Int, pages: [NovelTextViewportIndexPage]) -> Int {
        let spreads = makePagedSpreads(from: pages)
        let normalizedIndex = normalizedPagedPageIndex(preferredPage, pages: pages, pagedSpreads: spreads)
        guard pages.indices.contains(normalizedIndex) else {
            return currentDocument.view
        }
        return pages[normalizedIndex].documentView
    }

    private func makePagedSpreads(from pages: [NovelTextViewportIndexPage]) -> [ReaderPagedSpread] {
        guard !pages.isEmpty else { return [] }

        var spreads: [ReaderPagedSpread] = []
        var pageIndex = 0

        while pageIndex < pages.count {
            let leftPage = pages[pageIndex]
            let candidateRightIndex = pageIndex + 1
            let rightPageIndex: Int? = if pages.indices.contains(candidateRightIndex),
                                          pages[candidateRightIndex].documentView == leftPage.documentView {
                candidateRightIndex
            } else {
                nil
            }

            spreads.append(
                ReaderPagedSpread(
                    index: spreads.count,
                    leftPageIndex: leftPage.pageIndex,
                    rightPageIndex: rightPageIndex,
                    chapterTitle: leftPage.chapterTitle
                )
            )
            pageIndex += rightPageIndex == nil ? 1 : 2
        }

        return spreads
    }

    private func spreadIndex(
        forPageIndex pageIndex: Int,
        pages: [NovelTextViewportIndexPage],
        pagedSpreads: [ReaderPagedSpread]
    ) -> Int {
        guard isTwoPageSpreadActive else {
            return max(0, min(pageIndex, max(pages.count - 1, 0)))
        }

        let normalizedIndex = max(0, min(pageIndex, max(pages.count - 1, 0)))
        return pagedSpreads.first(where: { spread in
            spread.leftPageIndex == normalizedIndex || spread.rightPageIndex == normalizedIndex
        })?.index ?? 0
    }

    private func leftPageIndex(forSpreadIndex spreadIndex: Int, pagedSpreads: [ReaderPagedSpread]) -> Int {
        guard let spread = pagedSpreads.first(where: { $0.index == spreadIndex }) ?? pagedSpreads.last else {
            return 0
        }
        return spread.leftPageIndex
    }

    private func normalizedPagedPageIndex(
        _ pageIndex: Int,
        pages: [NovelTextViewportIndexPage],
        pagedSpreads: [ReaderPagedSpread]
    ) -> Int {
        let clampedIndex = max(0, min(pageIndex, max(pages.count - 1, 0)))
        guard isTwoPageSpreadActive else { return clampedIndex }
        return leftPageIndex(
            forSpreadIndex: spreadIndex(forPageIndex: clampedIndex, pages: pages, pagedSpreads: pagedSpreads),
            pagedSpreads: pagedSpreads
        )
    }

    private func resolveResumePoint(
        _ resumePoint: ReaderResumePoint,
        in renderedPages: [NovelTextViewportIndexPage]
    ) -> ReaderResolvedTarget? {
        let pagesInView = renderedPages.filter { $0.documentView == resumePoint.view }
        guard !pagesInView.isEmpty else {
            return nil
        }

        let candidatePages = pagesInView.filter { contains(segmentIndex: resumePoint.segmentIndex, in: $0) }
        let containingPage = candidatePages.first {
            contains(offset: resumePoint.segmentOffset, segmentIndex: resumePoint.segmentIndex, in: $0)
        }

        if let containingPage {
            return ReaderResolvedTarget(
                pageIndex: containingPage.pageIndex,
                intraPageProgress: intraPageProgress(for: resumePoint, in: containingPage),
                documentView: containingPage.documentView
            )
        }

        if let nearestPage = candidatePages.min(by: {
            distance(from: resumePoint.segmentOffset, segmentIndex: resumePoint.segmentIndex, to: $0)
                < distance(from: resumePoint.segmentOffset, segmentIndex: resumePoint.segmentIndex, to: $1)
        }) {
            return ReaderResolvedTarget(
                pageIndex: nearestPage.pageIndex,
                intraPageProgress: intraPageProgress(for: resumePoint, in: nearestPage),
                documentView: nearestPage.documentView
            )
        }

        if let chapterPage = pagesInView.first(where: { $0.chapterOrdinal == resumePoint.chapterOrdinal }) {
            return ReaderResolvedTarget(
                pageIndex: chapterPage.pageIndex,
                intraPageProgress: min(max(resumePoint.segmentProgress, 0), 1),
                documentView: chapterPage.documentView
            )
        }

        if let titlePage = pagesInView.first(where: { $0.chapterTitle == resumePoint.chapterTitle }) {
            return ReaderResolvedTarget(
                pageIndex: titlePage.pageIndex,
                intraPageProgress: min(max(resumePoint.segmentProgress, 0), 1),
                documentView: titlePage.documentView
            )
        }

        guard let firstPage = pagesInView.first else { return nil }
        return ReaderResolvedTarget(pageIndex: firstPage.pageIndex, intraPageProgress: 0, documentView: firstPage.documentView)
    }

    private func resolveViewportSample(_ sample: NovelTextViewportSample) -> ReaderResolvedTarget? {
        guard let page = snapshot.pages.first(where: {
            $0.pageIndex == sample.pageIndex && $0.documentView == sample.documentView
        }) else {
            return nil
        }
        let ranges = textRanges(for: page)
        guard !ranges.isEmpty else { return nil }

        let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
        var runningLength = 0

        for range in ranges {
            let length = max(range.length, 1)
            defer { runningLength += length }
            guard range.segmentIndex == sample.segmentIndex,
                  contains(offset: sample.segmentOffset, in: range) else {
                continue
            }
            let localOffset = min(max(sample.segmentOffset - range.startOffset, 0), length)
            let progress = Double(runningLength + localOffset) / Double(max(totalLength, 1))
            return ReaderResolvedTarget(
                pageIndex: page.pageIndex,
                intraPageProgress: min(max(progress, 0), 1),
                documentView: page.documentView
            )
        }

        return nil
    }

    private func contains(offset: Int, in page: NovelTextViewportIndexPage) -> Bool {
        let ranges = textRanges(for: page)
        return ranges.contains(where: { contains(offset: offset, in: $0) })
    }

    private func contains(offset: Int, segmentIndex: Int, in page: NovelTextViewportIndexPage) -> Bool {
        let matchingRanges = textRanges(for: page).filter { $0.segmentIndex == segmentIndex }
        return matchingRanges.contains { contains(offset: offset, in: $0) }
    }

    private func contains(segmentIndex: Int, in page: NovelTextViewportIndexPage) -> Bool {
        textRanges(for: page).contains { $0.segmentIndex == segmentIndex }
    }

    private func contains(offset: Int, in range: ReaderRenderedTextRange) -> Bool {
        if range.startOffset == range.endOffset {
            return offset <= range.startOffset
        }
        return offset >= range.startOffset && offset < range.endOffset
    }

    private func distance(from offset: Int, to page: NovelTextViewportIndexPage) -> Int {
        let ranges = textRanges(for: page)
        return ranges.map { distance(from: offset, to: $0) }.min() ?? 0
    }

    private func distance(from offset: Int, segmentIndex: Int, to page: NovelTextViewportIndexPage) -> Int {
        let matchingRanges = textRanges(for: page).filter { $0.segmentIndex == segmentIndex }
        if !matchingRanges.isEmpty {
            return matchingRanges.map { distance(from: offset, to: $0) }.min() ?? 0
        }
        return Int.max
    }

    private func distance(from offset: Int, to range: ReaderRenderedTextRange) -> Int {
        if contains(offset: offset, in: range) {
            return 0
        }
        if offset < range.startOffset {
            return range.startOffset - offset
        }
        return offset - range.endOffset
    }

    private func intraPageProgress(for resumePoint: ReaderResumePoint, in page: NovelTextViewportIndexPage) -> Double {
        let ranges = textRanges(for: page)
        if !ranges.isEmpty {
            let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
            var runningLength = 0

            for range in ranges {
                let length = max(range.length, 1)
                defer { runningLength += length }
                guard range.segmentIndex == resumePoint.segmentIndex else { continue }
                let localOffset = min(max(resumePoint.segmentOffset - range.startOffset, 0), length)
                let progress = Double(runningLength + localOffset) / Double(max(totalLength, 1))
                return min(max(progress, 0), 1)
            }
        }
        return min(max(resumePoint.segmentProgress, 0), 1)
    }

    private func textPosition(for intraPageProgress: Double, in page: NovelTextViewportIndexPage) -> ReaderPageTextPosition? {
        let ranges = textRanges(for: page)
        guard !ranges.isEmpty else { return nil }
        guard ranges.count > 1 else {
            return ranges.first.map {
                ReaderPageTextPosition(range: $0, progressInRange: min(max(intraPageProgress, 0), 1))
            }
        }

        let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
        let targetOffset = Int((Double(totalLength) * min(max(intraPageProgress, 0), 1)).rounded(.towardZero))
        var runningLength = 0

        for range in ranges {
            let length = max(range.length, 1)
            if targetOffset < runningLength + length {
                let progressInRange = Double(targetOffset - runningLength) / Double(length)
                return ReaderPageTextPosition(
                    range: range,
                    progressInRange: min(max(progressInRange, 0), 1)
                )
            }
            runningLength += length
        }

        return ranges.last.map {
            ReaderPageTextPosition(range: $0, progressInRange: 1)
        }
    }

    private func textRanges(for page: NovelTextViewportIndexPage) -> [ReaderRenderedTextRange] {
        page.ranges
    }
}

private struct ReaderResolvedTarget {
    let pageIndex: Int
    let intraPageProgress: Double
    let documentView: Int
}

private struct ReaderPageTextPosition {
    let range: ReaderRenderedTextRange
    let progressInRange: Double
}

private extension String {
    func droppingReaderPreviewCharacters(_ count: Int) -> String {
        guard count > 0 else { return self }
        guard count < self.count else { return "" }

        let start = index(startIndex, offsetBy: count)
        return String(self[start...])
    }
}
