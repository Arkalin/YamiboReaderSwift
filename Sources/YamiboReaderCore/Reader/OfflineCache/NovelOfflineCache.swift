import Foundation

public struct NovelOfflineCacheEntry: Codable, Hashable, Identifiable, Sendable {
    public var ownerTitle: String
    public var title: String
    public var document: ReaderPageDocument
    public var imageURLs: [URL]
    public var updatedAt: Date

    public var id: OfflineCacheEntryID {
        OfflineCacheEntryID(
            readerKind: .novel,
            ownerKey: ownerTitle,
            entryKey: Self.entryKey(document: document)
        )
    }

    public init(
        ownerTitle: String,
        title: String? = nil,
        document: ReaderPageDocument,
        imageURLs: [URL] = [],
        updatedAt: Date = .now
    ) {
        self.ownerTitle = ownerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if self.title.isEmpty {
            self.title = Self.defaultTitle(document: document)
        }
        self.document = document
        self.imageURLs = Self.uniqueURLs(imageURLs)
        self.updatedAt = updatedAt
    }

    public static func entryKey(document: ReaderPageDocument) -> String {
        entryKey(
            threadURL: document.threadURL,
            view: document.view,
            authorID: document.resolvedAuthorID,
            contentSource: document.contentSource
        )
    }

    public static func entryKey(
        threadURL: URL,
        view: Int,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) -> String {
        let identity = ReaderCacheIdentity(
            threadURL: threadURL,
            view: view,
            authorID: authorID,
            contentSource: contentSource
        )
        let source = resolvedContentSource(authorID: authorID, contentSource: contentSource)
        return [
            "tid",
            identity.threadID,
            "source",
            source.rawValue,
            "author",
            normalizedAuthorID(authorID) ?? "all",
            "view",
            String(identity.view)
        ].joined(separator: "_")
    }

    public static func defaultTitle(document: ReaderPageDocument) -> String {
        L10n.string("reader.page_number_spaced", document.view)
    }

    private static func resolvedContentSource(
        authorID: String?,
        contentSource: ReaderContentSource?
    ) -> ReaderContentSource {
        if normalizedAuthorID(authorID) != nil {
            return .authorFilteredPage
        }
        return contentSource ?? .fallbackUnfilteredPage
    }

    private static func normalizedAuthorID(_ authorID: String?) -> String? {
        let value = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var output: [URL] = []
        for url in urls where seen.insert(url.absoluteString).inserted {
            output.append(url)
        }
        return output
    }
}

public struct NovelOfflineCacheWorkRequest: Hashable, Sendable {
    public var ownerTitle: String
    public var title: String
    public var threadURL: URL
    public var view: Int
    public var authorID: String?
    public var contentSource: ReaderContentSource
    public var targetImageURLs: [URL]

    public var entryKey: String {
        NovelOfflineCacheEntry.entryKey(
            threadURL: threadURL,
            view: view,
            authorID: authorID,
            contentSource: contentSource
        )
    }

    public init(
        ownerTitle: String,
        title: String,
        threadURL: URL,
        view: Int,
        authorID: String? = nil,
        contentSource: ReaderContentSource = .fallbackUnfilteredPage,
        targetImageURLs: [URL] = []
    ) {
        self.ownerTitle = ownerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadURL = ReaderCacheIdentity.canonicalThreadURL(from: threadURL)
        self.view = max(1, view)
        self.authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.authorID?.isEmpty == true {
            self.authorID = nil
        }
        self.contentSource = self.authorID == nil ? contentSource : .authorFilteredPage
        self.targetImageURLs = Self.uniqueURLs(targetImageURLs)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var output: [URL] = []
        for url in urls where seen.insert(url.absoluteString).inserted {
            output.append(url)
        }
        return output
    }
}

public enum NovelOfflineCacheEnqueueResult: Hashable, Sendable {
    case alreadyCached(NovelOfflineCacheEntry)
    case alreadyQueued(OfflineCacheQueueWorkProjection)
    case enqueued(OfflineCacheQueueWorkProjection)

    public var enqueuedWork: OfflineCacheQueueWorkProjection? {
        if case let .enqueued(work) = self {
            return work
        }
        return nil
    }
}
