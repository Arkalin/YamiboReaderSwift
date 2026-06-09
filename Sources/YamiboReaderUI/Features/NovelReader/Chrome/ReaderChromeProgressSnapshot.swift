import YamiboReaderCore

public struct ReaderProgressChapterTick: Equatable, Sendable {
    public var chapter: ReaderChapter
    public var position: Double
    public var isCurrent: Bool

    public init(chapter: ReaderChapter, position: Double, isCurrent: Bool) {
        self.chapter = chapter
        self.position = position
        self.isCurrent = isCurrent
    }
}

private struct ReaderProgressScrubData: Equatable, Sendable {
    var readingMode: ReaderReadingMode
    var surfaceCount: Int
    var currentProgressPercent: Int
    var visibleSurfaceIndexes: [Int]
    var fallbackVisibleSurfaceIndex: Int
    var chapterTitlesBySurfaceIndex: [Int: String]
    var chapterTickStartIndexes: Set<Int>
    var isTwoPageSpreadActive: Bool

    func targetSurfaceIndex(for value: Double) -> Int {
        guard surfaceCount > 1 else { return 0 }
        switch readingMode {
        case .paged:
            let target = min(max(Int(value.rounded()), 0), max(surfaceCount - 1, 0))
            guard isTwoPageSpreadActive else { return target }
            return max(0, min(target - (target % 2), max(surfaceCount - 1, 0)))
        case .vertical:
            guard !visibleSurfaceIndexes.isEmpty,
                  visibleSurfaceIndexes.count > 1 else {
                return fallbackVisibleSurfaceIndex
            }
            let clampedPercent = min(max(value, 0), 100)
            let localSurfaceIndex = min(
                max(Int((clampedPercent / 100) * Double(visibleSurfaceIndexes.count - 1)), 0),
                max(visibleSurfaceIndexes.count - 1, 0)
            )
            return visibleSurfaceIndexes[localSurfaceIndex]
        }
    }

    func chapterTitle(for surfaceIndex: Int) -> String? {
        let clampedIndex = min(max(surfaceIndex, 0), max(surfaceCount - 1, 0))
        return chapterTitlesBySurfaceIndex[clampedIndex]
    }

    func chapterTickStartIndex(for surfaceIndex: Int) -> Int? {
        let clampedIndex = min(max(surfaceIndex, 0), max(surfaceCount - 1, 0))
        return chapterTickStartIndexes.contains(clampedIndex) ? clampedIndex : nil
    }
}

public struct ReaderChromeProgressSnapshot: Equatable, Sendable {
    public var readingMode: ReaderReadingMode
    public var visibleView: Int
    public var surfaceCount: Int
    public var currentSurfaceNumber: Int
    public var currentChapterTitle: String?
    public var progressText: String
    public var currentProgressFraction: Double
    public var currentProgressPercent: Int
    public var currentProgressPercentText: String
    public var progressChapterTicks: [ReaderProgressChapterTick]
    private var scrubData: ReaderProgressScrubData

    public static var empty: ReaderChromeProgressSnapshot {
        ReaderChromeProgressSnapshot(
            readingMode: .paged,
            visibleView: 1,
            surfaceCount: 1,
            currentSurfaceNumber: 1,
            currentChapterTitle: nil,
            progressText: "",
            currentProgressFraction: 0,
            currentProgressPercent: 0,
            currentProgressPercentText: "0%",
            progressChapterTicks: [],
            scrubData: ReaderProgressScrubData(
                readingMode: .paged,
                surfaceCount: 1,
                currentProgressPercent: 0,
                visibleSurfaceIndexes: [],
                fallbackVisibleSurfaceIndex: 0,
                chapterTitlesBySurfaceIndex: [:],
                chapterTickStartIndexes: [],
                isTwoPageSpreadActive: false
            )
        )
    }

    public init(presentation: NovelReaderPresentation) {
        let projection = presentation.progressProjection
        let chapter = presentation.readingState.currentChapterTitle ?? ""
        let progressText = if chapter.isEmpty {
            L10n.string(
                "reader.progress",
                projection.displayedPageLabel,
                max(projection.displayedPageCount, 1),
                projection.displayedView,
                max(presentation.readingState.maxView, 1)
            )
        } else {
            L10n.string(
                "reader.progress_with_chapter",
                projection.displayedPageLabel,
                max(projection.displayedPageCount, 1),
                projection.displayedView,
                max(presentation.readingState.maxView, 1),
                chapter
            )
        }
        let maxIndex = max(projection.surfaceCount - 1, 0)
        let currentChapterIndex = presentation.chapters.lastIndex {
            $0.startIndex <= projection.selectedSurfaceIndex
        }
        let progressChapterTicks: [ReaderProgressChapterTick] = {
            guard projection.surfaceCount > 1, !presentation.chapters.isEmpty else { return [] }
            var seenStartIndexes = Set<Int>()
            return presentation.chapters.enumerated().compactMap { index, chapter -> ReaderProgressChapterTick? in
                let clampedStartIndex = min(max(chapter.startIndex, 0), max(maxIndex, 1))
                guard seenStartIndexes.insert(clampedStartIndex).inserted else { return nil }
                return ReaderProgressChapterTick(
                    chapter: chapter,
                    position: Double(clampedStartIndex) / Double(max(maxIndex, 1)),
                    isCurrent: currentChapterIndex == index
                )
            }
        }()
        let chapterTitlesBySurfaceIndex = Self.chapterTitlesBySurfaceIndex(
            surfaces: presentation.surfaces,
            chapters: presentation.chapters,
            maxIndex: maxIndex
        )
        let tickStartIndexes = Set(presentation.chapters.map { min(max($0.startIndex, 0), maxIndex) })

        self.init(
            readingMode: projection.readingMode,
            visibleView: projection.displayedView,
            surfaceCount: projection.surfaceCount,
            currentSurfaceNumber: projection.currentSurfaceNumber,
            currentChapterTitle: presentation.readingState.currentChapterTitle,
            progressText: progressText,
            currentProgressFraction: projection.currentProgressFraction,
            currentProgressPercent: projection.currentProgressPercent,
            currentProgressPercentText: projection.currentProgressPercentText,
            progressChapterTicks: progressChapterTicks,
            scrubData: ReaderProgressScrubData(
                readingMode: projection.readingMode,
                surfaceCount: projection.surfaceCount,
                currentProgressPercent: projection.currentProgressPercent,
                visibleSurfaceIndexes: projection.visibleSurfaceIndexes,
                fallbackVisibleSurfaceIndex: projection.fallbackVisibleSurfaceIndex,
                chapterTitlesBySurfaceIndex: chapterTitlesBySurfaceIndex,
                chapterTickStartIndexes: tickStartIndexes,
                isTwoPageSpreadActive: projection.usesTwoPageSpread
            )
        )
    }

    private init(
        readingMode: ReaderReadingMode,
        visibleView: Int,
        surfaceCount: Int,
        currentSurfaceNumber: Int,
        currentChapterTitle: String?,
        progressText: String,
        currentProgressFraction: Double,
        currentProgressPercent: Int,
        currentProgressPercentText: String,
        progressChapterTicks: [ReaderProgressChapterTick],
        scrubData: ReaderProgressScrubData
    ) {
        self.readingMode = readingMode
        self.visibleView = max(visibleView, 1)
        self.surfaceCount = max(surfaceCount, 1)
        self.currentSurfaceNumber = min(max(currentSurfaceNumber, 1), self.surfaceCount)
        self.currentChapterTitle = currentChapterTitle
        self.progressText = progressText
        self.currentProgressFraction = min(max(currentProgressFraction, 0), 1)
        self.currentProgressPercent = min(max(currentProgressPercent, 0), 100)
        self.currentProgressPercentText = currentProgressPercentText
        self.progressChapterTicks = progressChapterTicks
        self.scrubData = scrubData
    }

    public func progressSliderLabelText(
        isEditing: Bool,
        sliderValue: Double,
        targetSurfaceIndex: Int
    ) -> String {
        if readingMode == .vertical {
            guard isEditing else { return currentProgressPercentText }
            let percent = Int(min(max(sliderValue, 0), 100).rounded())
            return "\(percent)%"
        }

        guard isEditing else {
            return "\(currentSurfaceNumber) / \(surfaceCount)"
        }
        let page = min(max(targetSurfaceIndex + 1, 1), surfaceCount)
        return "\(page) / \(surfaceCount)"
    }

    public func targetSurfaceIndex(forProgressValue value: Double) -> Int {
        scrubData.targetSurfaceIndex(for: value)
    }

    public func chapterTitle(forSurfaceIndex surfaceIndex: Int) -> String? {
        scrubData.chapterTitle(for: surfaceIndex)
    }

    public func progressChapterTickStartIndex(forSurfaceIndex surfaceIndex: Int) -> Int? {
        scrubData.chapterTickStartIndex(for: surfaceIndex)
    }

    public var progressScrubContext: ReaderProgressScrubContext {
        ReaderProgressScrubContext(
            readingMode: scrubData.readingMode,
            surfaceCount: scrubData.surfaceCount,
            currentProgressPercent: scrubData.currentProgressPercent,
            targetSurfaceIndex: { value in
                scrubData.targetSurfaceIndex(for: value)
            },
            chapterTitle: { surfaceIndex in
                scrubData.chapterTitle(for: surfaceIndex)
            },
            chapterTickStartIndex: { surfaceIndex in
                scrubData.chapterTickStartIndex(for: surfaceIndex)
            }
        )
    }

    private static func chapterTitlesBySurfaceIndex(
        surfaces: [NovelReaderSurface],
        chapters: [ReaderChapter],
        maxIndex: Int
    ) -> [Int: String] {
        guard maxIndex >= 0, !surfaces.isEmpty else { return [:] }
        var result: [Int: String] = [:]
        var chapterIndex = 0
        let sortedChapters = chapters.sorted { $0.startIndex < $1.startIndex }
        for index in surfaces.indices {
            while chapterIndex + 1 < sortedChapters.count,
                  sortedChapters[chapterIndex + 1].startIndex <= index {
                chapterIndex += 1
            }
            if let title = surfaces[index].chapterTitle {
                result[index] = title
            } else if sortedChapters.indices.contains(chapterIndex),
                      sortedChapters[chapterIndex].startIndex <= index {
                result[index] = sortedChapters[chapterIndex].title
            }
        }
        return result
    }
}
