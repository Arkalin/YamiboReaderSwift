import Foundation

public struct MangaReaderPresentation: Hashable, Sendable {
    public var state: MangaReaderPresentationState
    public var settings: MangaReaderSettings

    public init(
        state: MangaReaderPresentationState,
        settings: MangaReaderSettings = MangaReaderSettings()
    ) {
        self.state = state
        self.settings = settings
    }
}

public enum MangaReaderPresentationState: Hashable, Sendable {
    case loading(MangaReaderLoadingPresentation)
    case loaded(MangaReaderLoadedPresentation)
    case failed(MangaReaderErrorPresentation)
}

public struct MangaReaderLoadingPresentation: Hashable, Sendable {
    public var title: String

    public init(title: String) {
        self.title = title
    }
}

public struct MangaReaderLoadedPresentation: Hashable, Sendable {
    public var title: String
    public var directoryTitle: String
    public var pages: [MangaReaderPageProjection]
    public var currentPage: MangaReaderPageProjection?
    public var currentPageIndex: Int?
    public var readingPosition: MangaReadingPosition?

    public init(
        title: String,
        directoryTitle: String,
        pages: [MangaReaderPageProjection],
        currentPage: MangaReaderPageProjection?,
        currentPageIndex: Int?,
        readingPosition: MangaReadingPosition?
    ) {
        self.title = title
        self.directoryTitle = directoryTitle
        self.pages = pages
        self.currentPage = currentPage
        self.currentPageIndex = currentPageIndex
        self.readingPosition = readingPosition
    }
}

public struct MangaReaderErrorPresentation: Hashable, Sendable {
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}
