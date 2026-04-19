import Foundation

public enum MangaLaunchSource: String, Codable, Hashable, Sendable {
    case forum
    case favorites
    case resume
}

public struct MangaLaunchContext: Codable, Hashable, Identifiable, Sendable {
    public var originalThreadURL: URL
    public var chapterURL: URL
    public var displayTitle: String
    public var source: MangaLaunchSource
    public var initialPage: Int
    public var directoryName: String?

    public var id: String {
        "\(originalThreadURL.absoluteString)#\(chapterURL.absoluteString)"
    }

    public init(
        originalThreadURL: URL,
        chapterURL: URL,
        displayTitle: String,
        source: MangaLaunchSource,
        initialPage: Int = 0,
        directoryName: String? = nil
    ) {
        self.originalThreadURL = originalThreadURL
        self.chapterURL = chapterURL
        self.displayTitle = displayTitle
        self.source = source
        self.initialPage = max(0, initialPage)
        self.directoryName = directoryName
    }
}

public struct MangaWebContext: Codable, Hashable, Identifiable, Sendable {
    public var currentURL: URL
    public var originalThreadURL: URL
    public var source: MangaLaunchSource
    public var initialPage: Int
    public var autoOpenNative: Bool
    public var waitingForNativeReturn: Bool

    public var id: String {
        "\(originalThreadURL.absoluteString)#\(currentURL.absoluteString)#\(initialPage)"
    }

    public init(
        currentURL: URL,
        originalThreadURL: URL,
        source: MangaLaunchSource,
        initialPage: Int = 0,
        autoOpenNative: Bool = false,
        waitingForNativeReturn: Bool = false
    ) {
        self.currentURL = currentURL
        self.originalThreadURL = originalThreadURL
        self.source = source
        self.initialPage = max(0, initialPage)
        self.autoOpenNative = autoOpenNative
        self.waitingForNativeReturn = waitingForNativeReturn
    }

    public func updating(
        currentURL: URL? = nil,
        initialPage: Int? = nil,
        autoOpenNative: Bool? = nil,
        waitingForNativeReturn: Bool? = nil
    ) -> MangaWebContext {
        MangaWebContext(
            currentURL: currentURL ?? self.currentURL,
            originalThreadURL: originalThreadURL,
            source: source,
            initialPage: initialPage ?? self.initialPage,
            autoOpenNative: autoOpenNative ?? self.autoOpenNative,
            waitingForNativeReturn: waitingForNativeReturn ?? self.waitingForNativeReturn
        )
    }
}

public enum MangaPresentationRoute: Hashable, Sendable {
    case native(MangaLaunchContext)
    case web(MangaWebContext)
}

public struct MangaProbePayload: Hashable, Sendable {
    public var images: [URL]
    public var title: String
    public var html: String?
    public var sectionName: String?

    public init(images: [URL], title: String, html: String? = nil, sectionName: String? = nil) {
        self.images = images
        self.title = title
        self.html = html
        self.sectionName = sectionName
    }
}

public enum MangaProbeFailureReason: String, Hashable, Sendable {
    case timeout
    case retryableNetwork
    case notManga
    case noImages
    case webProcessTerminated
}

public enum MangaProbeOutcome: Hashable, Sendable {
    case success(MangaProbePayload)
    case fallback(reason: MangaProbeFailureReason, suggestedWebContext: MangaWebContext)
}

public enum MangaChapterTransitionSource: String, Hashable, Sendable {
    case adjacent
    case directory
}

public enum MangaChapterTransitionState: Hashable, Sendable {
    case idle
    case loading(targetTID: String, source: MangaChapterTransitionSource)
    case failed(message: String)
}

public enum MangaReaderNavigationRequest: Hashable, Sendable {
    case reopenNative(MangaLaunchContext)
    case fallbackWeb(MangaWebContext)
}

public enum MangaDirectoryStrategy: String, Codable, Hashable, Sendable {
    case tag
    case links
    case pendingSearch
    case searched
}

public struct MangaDirectory: Codable, Hashable, Sendable, Identifiable {
    public var cleanBookName: String
    public var strategy: MangaDirectoryStrategy
    public var sourceKey: String
    public var chapters: [MangaChapter]
    public var lastUpdatedAt: Date?
    public var searchKeyword: String?

    public var id: String { cleanBookName }

    public init(
        cleanBookName: String,
        strategy: MangaDirectoryStrategy,
        sourceKey: String,
        chapters: [MangaChapter] = [],
        lastUpdatedAt: Date? = nil,
        searchKeyword: String? = nil
    ) {
        self.cleanBookName = cleanBookName
        self.strategy = strategy
        self.sourceKey = sourceKey
        self.chapters = chapters
        self.lastUpdatedAt = lastUpdatedAt
        self.searchKeyword = searchKeyword
    }
}

public struct MangaDirectoryUpdateResult: Hashable, Sendable {
    public var directory: MangaDirectory
    public var searchPerformed: Bool

    public init(directory: MangaDirectory, searchPerformed: Bool) {
        self.directory = directory
        self.searchPerformed = searchPerformed
    }
}

public struct MangaChapterDocument: Hashable, Sendable {
    public var tid: String
    public var chapterTitle: String
    public var chapterURL: URL
    public var pages: [URL]
    public var html: String

    public init(
        tid: String,
        chapterTitle: String,
        chapterURL: URL,
        pages: [URL],
        html: String
    ) {
        self.tid = tid
        self.chapterTitle = chapterTitle
        self.chapterURL = chapterURL
        self.pages = pages
        self.html = html
    }
}

public struct MangaPage: Hashable, Identifiable, Sendable {
    public var tid: String
    public var chapterTitle: String
    public var imageURL: URL
    public var globalIndex: Int
    public var localIndex: Int
    public var chapterTotalPages: Int
    public var chapterURL: URL

    public var id: String {
        "\(tid)#\(localIndex)"
    }

    public init(
        tid: String,
        chapterTitle: String,
        imageURL: URL,
        globalIndex: Int,
        localIndex: Int,
        chapterTotalPages: Int,
        chapterURL: URL
    ) {
        self.tid = tid
        self.chapterTitle = chapterTitle
        self.imageURL = imageURL
        self.globalIndex = globalIndex
        self.localIndex = localIndex
        self.chapterTotalPages = chapterTotalPages
        self.chapterURL = chapterURL
    }
}

public struct MangaProgress: Codable, Hashable, Sendable {
    public var chapterURL: URL
    public var chapterTitle: String
    public var pageIndex: Int

    public init(chapterURL: URL, chapterTitle: String, pageIndex: Int) {
        self.chapterURL = chapterURL
        self.chapterTitle = chapterTitle
        self.pageIndex = max(0, pageIndex)
    }
}

public enum MangaReadingMode: String, Codable, Hashable, CaseIterable, Sendable {
    case paged
    case vertical

    public var title: String {
        switch self {
        case .paged: "横向分页"
        case .vertical: "纵向滚动"
        }
    }
}

public enum MangaDirectorySortOrder: String, Codable, Hashable, CaseIterable, Sendable {
    case ascending
    case descending

    public var title: String {
        switch self {
        case .ascending: "正序"
        case .descending: "倒序"
        }
    }
}

public struct MangaReaderSettings: Codable, Hashable, Sendable {
    public var readingMode: MangaReadingMode
    public var brightness: Double
    public var zoomEnabled: Bool
    public var showsSystemStatusBar: Bool
    public var directorySortOrder: MangaDirectorySortOrder

    public init(
        readingMode: MangaReadingMode = .vertical,
        brightness: Double = 1,
        zoomEnabled: Bool = true,
        showsSystemStatusBar: Bool = true,
        directorySortOrder: MangaDirectorySortOrder = .ascending
    ) {
        self.readingMode = readingMode
        self.brightness = brightness
        self.zoomEnabled = zoomEnabled
        self.showsSystemStatusBar = showsSystemStatusBar
        self.directorySortOrder = directorySortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case readingMode
        case brightness
        case zoomEnabled
        case showsSystemStatusBar
        case directorySortOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readingMode = try container.decodeIfPresent(MangaReadingMode.self, forKey: .readingMode) ?? .vertical
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
        zoomEnabled = try container.decodeIfPresent(Bool.self, forKey: .zoomEnabled) ?? true
        showsSystemStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showsSystemStatusBar) ?? true
        directorySortOrder = try container.decodeIfPresent(MangaDirectorySortOrder.self, forKey: .directorySortOrder) ?? .ascending
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(zoomEnabled, forKey: .zoomEnabled)
        try container.encode(showsSystemStatusBar, forKey: .showsSystemStatusBar)
        try container.encode(directorySortOrder, forKey: .directorySortOrder)
    }
}

public enum ThreadOpenTarget: Hashable, Sendable {
    case novel(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case web(URL)
}
