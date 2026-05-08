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
    public var pages: [ReaderRenderedPage]
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

    public init(
        pages: [ReaderRenderedPage],
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
        currentAuthorID: String?
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

    public init(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        preferredPage: Int = 0,
        resumePoint: ReaderResumePoint? = nil,
        usesPadPresentation: Bool = false,
        currentAuthorID: String? = nil
    ) {
        self.settings = settings
        self.layout = layout
        self.currentDocument = document
        self.usesPadPresentation = usesPadPresentation
        self.pendingResumePoint = nil
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
            currentAuthorID: document.resolvedAuthorID ?? currentAuthorID
        )
        applyPagination(for: document, preferredPage: preferredPage, preferredResumePoint: resumePoint)
    }

    private var isTwoPageSpreadActive: Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            layout.width > layout.height
    }

    public mutating func applySettings(_ newSettings: ReaderAppearanceSettings) {
        let oldSettings = settings
        let shouldRepaginate = oldSettings != newSettings
        let resumePoint = shouldRepaginate ? captureNovelReadingPosition() : nil
        if shouldRepaginate {
            pendingResumePoint = resumePoint
            pendingResumeRequiresLayoutSync = oldSettings.readingMode != newSettings.readingMode
        }
        settings = newSettings
        guard shouldRepaginate else { return }
        applyPagination(for: currentDocument, preferredPage: snapshot.currentPageIndex, preferredResumePoint: resumePoint)
        clearPendingResumePointIfSettled()
    }

    public mutating func updateLayout(_ layout: ReaderContainerLayout) {
        guard self.layout != layout else { return }
        let resumePoint = pendingResumePoint ?? captureNovelReadingPosition()
        self.layout = layout
        applyPagination(for: currentDocument, preferredPage: snapshot.currentPageIndex, preferredResumePoint: resumePoint)
        clearPendingResumePointIfSettled()
    }

    public mutating func updatePagedPresentationEnvironment(isPad: Bool) {
        guard usesPadPresentation != isPad else { return }
        usesPadPresentation = isPad
        guard settings.readingMode == .paged else { return }
        applyPagination(for: currentDocument, preferredPage: snapshot.currentPageIndex, preferredResumePoint: captureNovelReadingPosition())
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

        if let prefetchedStartIndex = snapshot.prefetchedStartIndex,
           settings.readingMode == .vertical,
           targetIndex >= prefetchedStartIndex {
            return .promotePrefetched(preferredPage: targetIndex - prefetchedStartIndex, resumePoint: nil)
        }

        if settings.readingMode == .paged,
           prefetchedDocument?.view == snapshot.currentView + 1 {
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
    }

    public mutating func acceptPrefetchedDocument(_ document: ReaderPageDocument) {
        prefetchedDocument = document
        snapshot.maxView = max(snapshot.maxView, document.maxView)
        if settings.readingMode == .vertical {
            applyPagination(
                for: currentDocument,
                preferredPage: snapshot.currentPageIndex,
                preferredResumePoint: captureNovelReadingPosition()
            )
        }
    }

    public mutating func promotePrefetchedDocument(
        preferredPage: Int = 0,
        resumePoint: ReaderResumePoint? = nil
    ) {
        guard let nextDocument = prefetchedDocument else { return }
        currentDocument = nextDocument
        prefetchedDocument = nil
        let effectiveResumePoint = resumePoint?.view == nextDocument.view ? resumePoint : nil
        applyPagination(for: nextDocument, preferredPage: preferredPage, preferredResumePoint: effectiveResumePoint)
    }

    public func captureNovelReadingPosition() -> ReaderResumePoint? {
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

    private func chapterTitle(for pageIndex: Int, pages: [ReaderRenderedPage], chapters: [ReaderChapter]) -> String? {
        guard pages.indices.contains(pageIndex) else {
            return chapters.last(where: { $0.startIndex <= pageIndex })?.title
        }
        return pages[pageIndex].chapterTitle ?? chapters.last(where: { $0.startIndex <= pageIndex })?.title
    }

    private var currentRenderedPage: ReaderRenderedPage? {
        let normalizedIndex = normalizedPagedPageIndex(
            snapshot.currentPageIndex,
            pages: snapshot.pages,
            pagedSpreads: snapshot.pagedSpreads
        )
        guard snapshot.pages.indices.contains(normalizedIndex) else { return nil }
        return snapshot.pages[normalizedIndex]
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
    ) {
        let paginationLayout = effectivePaginationLayout
        let pagination = ReaderPaginator.paginate(document: document, settings: settings, layout: paginationLayout)
        var renderedPages = pagination.pages
        var renderedChapters = pagination.chapters
        var prefetchedStartIndex: Int?

        if settings.readingMode == .vertical,
           let prefetchedDocument,
           prefetchedDocument.view == document.view + 1 {
            let nextPagination = ReaderPaginator.paginate(document: prefetchedDocument, settings: settings, layout: paginationLayout)
            let startIndex = renderedPages.count
            prefetchedStartIndex = startIndex
            renderedPages += nextPagination.pages.enumerated().map { offset, page in
                ReaderRenderedPage(
                    index: startIndex + offset,
                    blocks: page.blocks,
                    documentView: page.documentView,
                    chapterOrdinal: page.chapterOrdinal,
                    chapterTitle: page.chapterTitle,
                    segmentIndex: page.segmentIndex,
                    segmentStartOffset: page.segmentStartOffset,
                    segmentEndOffset: page.segmentEndOffset,
                    textRanges: page.textRanges
                )
            }
            renderedChapters += nextPagination.chapters.map { chapter in
                ReaderChapter(
                    ordinal: chapter.ordinal,
                    title: chapter.title,
                    startIndex: chapter.startIndex + startIndex
                )
            }
        }

        let pages = renderedPages.enumerated().map { index, page in
            ReaderRenderedPage(
                index: index,
                blocks: page.blocks,
                documentView: page.documentView,
                chapterOrdinal: page.chapterOrdinal,
                chapterTitle: page.chapterTitle,
                segmentIndex: page.segmentIndex,
                segmentStartOffset: page.segmentStartOffset,
                segmentEndOffset: page.segmentEndOffset,
                textRanges: page.textRanges
            )
        }
        let fallbackTarget = ReaderResolvedTarget(
            pageIndex: max(0, min(preferredPage, max(pages.count - 1, 0))),
            intraPageProgress: 0,
            documentView: displayedViewCandidate(for: preferredPage, pages: pages)
        )
        let effectiveResumePoint = pendingResumePoint ?? preferredResumePoint
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
            currentAuthorID: document.resolvedAuthorID ?? snapshot.currentAuthorID
        )
    }

    private func displayedViewCandidate(for preferredPage: Int, pages: [ReaderRenderedPage]) -> Int {
        let spreads = makePagedSpreads(from: pages)
        let normalizedIndex = normalizedPagedPageIndex(preferredPage, pages: pages, pagedSpreads: spreads)
        guard pages.indices.contains(normalizedIndex) else {
            return currentDocument.view
        }
        return pages[normalizedIndex].documentView
    }

    private func makePagedSpreads(from pages: [ReaderRenderedPage]) -> [ReaderPagedSpread] {
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
                    leftPageIndex: leftPage.index,
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
        pages: [ReaderRenderedPage],
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
        pages: [ReaderRenderedPage],
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
        in renderedPages: [ReaderRenderedPage]
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
                pageIndex: containingPage.index,
                intraPageProgress: intraPageProgress(for: resumePoint, in: containingPage),
                documentView: containingPage.documentView
            )
        }

        if let nearestPage = candidatePages.min(by: {
            distance(from: resumePoint.segmentOffset, segmentIndex: resumePoint.segmentIndex, to: $0)
                < distance(from: resumePoint.segmentOffset, segmentIndex: resumePoint.segmentIndex, to: $1)
        }) {
            return ReaderResolvedTarget(
                pageIndex: nearestPage.index,
                intraPageProgress: intraPageProgress(for: resumePoint, in: nearestPage),
                documentView: nearestPage.documentView
            )
        }

        if let chapterPage = pagesInView.first(where: { $0.chapterOrdinal == resumePoint.chapterOrdinal }) {
            return ReaderResolvedTarget(
                pageIndex: chapterPage.index,
                intraPageProgress: min(max(resumePoint.segmentProgress, 0), 1),
                documentView: chapterPage.documentView
            )
        }

        if let titlePage = pagesInView.first(where: { $0.chapterTitle == resumePoint.chapterTitle }) {
            return ReaderResolvedTarget(
                pageIndex: titlePage.index,
                intraPageProgress: min(max(resumePoint.segmentProgress, 0), 1),
                documentView: titlePage.documentView
            )
        }

        guard let firstPage = pagesInView.first else { return nil }
        return ReaderResolvedTarget(pageIndex: firstPage.index, intraPageProgress: 0, documentView: firstPage.documentView)
    }

    private func contains(offset: Int, in page: ReaderRenderedPage) -> Bool {
        if !page.textRanges.isEmpty,
           page.textRanges.contains(where: { contains(offset: offset, in: $0) }) {
            return true
        }
        if page.segmentStartOffset == page.segmentEndOffset {
            return offset <= page.segmentStartOffset
        }
        return offset >= page.segmentStartOffset && offset < page.segmentEndOffset
    }

    private func contains(offset: Int, segmentIndex: Int, in page: ReaderRenderedPage) -> Bool {
        let matchingRanges = page.textRanges.filter { $0.segmentIndex == segmentIndex }
        if !matchingRanges.isEmpty {
            return matchingRanges.contains { contains(offset: offset, in: $0) }
        }
        guard page.segmentIndex == segmentIndex else { return false }
        return contains(offset: offset, in: page)
    }

    private func contains(segmentIndex: Int, in page: ReaderRenderedPage) -> Bool {
        page.textRanges.contains { $0.segmentIndex == segmentIndex } || page.segmentIndex == segmentIndex
    }

    private func contains(offset: Int, in range: ReaderRenderedTextRange) -> Bool {
        if range.startOffset == range.endOffset {
            return offset <= range.startOffset
        }
        return offset >= range.startOffset && offset < range.endOffset
    }

    private func distance(from offset: Int, to page: ReaderRenderedPage) -> Int {
        if !page.textRanges.isEmpty {
            return page.textRanges.map { distance(from: offset, to: $0) }.min() ?? 0
        }
        if offset < page.segmentStartOffset {
            return page.segmentStartOffset - offset
        }
        return offset - page.segmentEndOffset
    }

    private func distance(from offset: Int, segmentIndex: Int, to page: ReaderRenderedPage) -> Int {
        let matchingRanges = page.textRanges.filter { $0.segmentIndex == segmentIndex }
        if !matchingRanges.isEmpty {
            return matchingRanges.map { distance(from: offset, to: $0) }.min() ?? 0
        }
        return distance(from: offset, to: page)
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

    private func intraPageProgress(for resumePoint: ReaderResumePoint, in page: ReaderRenderedPage) -> Double {
        if !page.textRanges.isEmpty {
            let totalLength = page.textRanges.reduce(0) { $0 + max($1.length, 1) }
            var runningLength = 0

            for range in page.textRanges {
                let length = max(range.length, 1)
                defer { runningLength += length }
                guard range.segmentIndex == resumePoint.segmentIndex else { continue }
                let localOffset = min(max(resumePoint.segmentOffset - range.startOffset, 0), length)
                let progress = Double(runningLength + localOffset) / Double(max(totalLength, 1))
                return min(max(progress, 0), 1)
            }
        }
        let length = max(page.segmentEndOffset - page.segmentStartOffset, 0)
        guard length > 0 else {
            return min(max(resumePoint.segmentProgress, 0), 1)
        }
        let progress = Double(resumePoint.segmentOffset - page.segmentStartOffset) / Double(length)
        return min(max(progress, 0), 1)
    }

    private func textPosition(for intraPageProgress: Double, in page: ReaderRenderedPage) -> ReaderPageTextPosition? {
        guard !page.textRanges.isEmpty else { return nil }
        guard page.textRanges.count > 1 else {
            return page.textRanges.first.map {
                ReaderPageTextPosition(range: $0, progressInRange: min(max(intraPageProgress, 0), 1))
            }
        }

        let totalLength = page.textRanges.reduce(0) { $0 + max($1.length, 1) }
        let targetOffset = Int((Double(totalLength) * min(max(intraPageProgress, 0), 1)).rounded(.towardZero))
        var runningLength = 0

        for range in page.textRanges {
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

        return page.textRanges.last.map {
            ReaderPageTextPosition(range: $0, progressInRange: 1)
        }
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
