import Foundation

public actor ForumCacheStore {
    private static let schemaVersion = 1
    public static let homeTTL: TimeInterval = 12 * 60 * 60
    public static let boardTTL: TimeInterval = 2 * 60 * 60
    public static let threadPageTTL: TimeInterval = 24 * 60 * 60
    private static let threadPageMaxEntries = 50

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let threadPageIndexURL: URL
    private let now: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("forum-cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("forum-cache", isDirectory: true)
        self.threadPageIndexURL = self.baseDirectory.appendingPathComponent("thread_pages_index.json", isDirectory: false)
        self.now = now
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadHome(allowExpired: Bool = false) async -> ForumHomePage? {
        guard let entry: ForumCacheEntry<ForumHomePage> = load(fileName: "home.json") else { return nil }
        guard allowExpired || !isExpired(entry.fetchedAt, ttl: Self.homeTTL) else { return nil }
        return entry.value
    }

    public func saveHome(_ page: ForumHomePage) async throws {
        try save(ForumCacheEntry(value: page, fetchedAt: page.fetchedAt), fileName: "home.json")
    }

    public func loadBoard(
        fid: String,
        page: Int = 1,
        filterID: String? = nil,
        orderFilter: String? = nil,
        orderBy: String? = nil,
        allowExpired: Bool = false
    ) async -> ForumBoardPage? {
        guard let entry: ForumCacheEntry<ForumBoardPage> = load(fileName: boardFileName(fid: fid, page: page, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy)) else {
            return nil
        }
        guard allowExpired || !isExpired(entry.fetchedAt, ttl: Self.boardTTL) else { return nil }
        return entry.value
    }

    public func saveBoard(
        _ page: ForumBoardPage,
        fid: String,
        pageNumber: Int = 1,
        filterID: String? = nil,
        orderFilter: String? = nil,
        orderBy: String? = nil
    ) async throws {
        try save(
            ForumCacheEntry(value: page, fetchedAt: page.fetchedAt),
            fileName: boardFileName(fid: fid, page: pageNumber, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy)
        )
    }

    public func loadThreadPage(
        thread: ThreadIdentity,
        page: Int = 1,
        authorID: String? = nil,
        allowExpired: Bool = false
    ) async -> ForumThreadPage? {
        guard let entry: ForumCacheEntry<ForumThreadPage> = load(
            fileName: threadPageFileName(thread: thread, page: page, authorID: authorID)
        ) else {
            return nil
        }
        guard allowExpired || !isExpired(entry.fetchedAt, ttl: Self.threadPageTTL) else { return nil }
        return entry.value
    }

    public func cachedThreadPageViews(
        thread: ThreadIdentity,
        authorID: String? = nil,
        allowExpired: Bool = false
    ) async -> Set<Int> {
        let normalizedAuthorID = authorID?.nilIfBlank
        return Set(loadThreadPageIndex().values.compactMap { entry -> Int? in
            guard entry.threadURL == thread.canonicalURL,
                  entry.authorID == normalizedAuthorID,
                  allowExpired || !isExpired(entry.fetchedAt, ttl: Self.threadPageTTL),
                  fileManager.fileExists(atPath: baseDirectory.appendingPathComponent(entry.fileName, isDirectory: false).path) else {
                return nil
            }
            return entry.page
        })
    }

    public func saveThreadPage(
        _ page: ForumThreadPage,
        thread: ThreadIdentity,
        pageNumber: Int = 1,
        authorID: String? = nil
    ) async throws {
        var page = page
        if page.pageNavigation?.currentPage == nil {
            page.pageNavigation = ForumPageNavigation(
                currentPage: max(1, pageNumber),
                totalPages: page.pageNavigation?.totalPages
            )
        }
        let fetchedAt = now()
        let fileName = threadPageFileName(thread: thread, page: pageNumber, authorID: authorID)
        try save(
            ForumCacheEntry(value: page, fetchedAt: fetchedAt),
            fileName: fileName
        )
        var index = loadThreadPageIndex()
        index[fileName] = ThreadPageIndexEntry(
            fileName: fileName,
            threadURL: thread.canonicalURL,
            page: max(1, pageNumber),
            authorID: authorID?.nilIfBlank,
            fetchedAt: fetchedAt
        )
        try persistThreadPageIndex(index)
        try pruneThreadPageCache()
    }

    public func clearThreadPages(thread: ThreadIdentity) async throws {
        let prefix = threadPageFilePrefix(thread: thread)
        for fileURL in threadPageFileURLs() where fileURL.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: fileURL)
        }
        var index = loadThreadPageIndex()
        index = index.filter { $0.value.threadURL != thread.canonicalURL }
        try persistThreadPageIndex(index)
    }

    public func deleteThreadPages(
        _ pages: Set<Int>,
        thread: ThreadIdentity,
        authorID: String?
    ) async throws {
        let normalizedAuthorID = authorID?.nilIfBlank
        let normalizedPages = Set(pages.map { max(1, $0) })
        guard !normalizedPages.isEmpty else { return }
        var index = loadThreadPageIndex()
        for entry in index.values {
            guard entry.threadURL == thread.canonicalURL,
                  entry.authorID == normalizedAuthorID,
                  normalizedPages.contains(entry.page) else {
                continue
            }
            try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(entry.fileName, isDirectory: false))
            index.removeValue(forKey: entry.fileName)
        }
        try persistThreadPageIndex(index)
    }

    public func clearAll() async throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.removeItem(at: baseDirectory)
    }

    private func load<Value: Codable>(fileName: String) -> ForumCacheEntry<Value>? {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(ForumCacheEnvelope<Value>.self, from: data),
              envelope.version == Self.schemaVersion else {
            return nil
        }
        return envelope.entry
    }

    private func save<Value: Codable>(_ entry: ForumCacheEntry<Value>, fileName: String) throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(ForumCacheEnvelope(version: Self.schemaVersion, entry: entry))
        try data.write(to: baseDirectory.appendingPathComponent(fileName, isDirectory: false), options: [.atomic])
    }

    private func isExpired(_ fetchedAt: Date, ttl: TimeInterval) -> Bool {
        now().timeIntervalSince(fetchedAt) > ttl
    }

    private func boardFileName(fid: String, page: Int, filterID: String?, orderFilter: String?, orderBy: String?) -> String {
        let key = [
            fid,
            String(max(1, page)),
            filterID?.nilIfBlank ?? "all",
            orderFilter?.nilIfBlank ?? "default",
            orderBy?.nilIfBlank ?? "default"
        ].joined(separator: "_")
        return "board_\(stableIdentifier(for: key)).json"
    }

    private func threadPageFileName(thread: ThreadIdentity, page: Int, authorID: String?) -> String {
        let key = [
            thread.canonicalURL.absoluteString,
            String(max(1, page)),
            authorID?.nilIfBlank ?? "all"
        ].joined(separator: "_")
        return "\(threadPageFilePrefix(thread: thread))\(stableIdentifier(for: key)).json"
    }

    private func threadPageFilePrefix(thread: ThreadIdentity) -> String {
        "thread_\(stableIdentifier(for: thread.canonicalURL.absoluteString))_"
    }

    private func threadPageFileURLs() -> [URL] {
        guard fileManager.fileExists(atPath: baseDirectory.path),
              let urls = try? fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }
        return urls.filter { $0.lastPathComponent.hasPrefix("thread_") }
    }

    private func pruneThreadPageCache() throws {
        let entries = threadPageFileURLs().compactMap { url -> (url: URL, fetchedAt: Date)? in
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? decoder.decode(ForumCacheEnvelope<ForumThreadPage>.self, from: data),
                  envelope.version == Self.schemaVersion else {
                return nil
            }
            return (url, envelope.entry.fetchedAt)
        }
        let expired = entries.filter { isExpired($0.fetchedAt, ttl: Self.threadPageTTL) }
        for entry in expired {
            try? fileManager.removeItem(at: entry.url)
        }

        let retained = entries
            .filter { candidate in !expired.contains { $0.url == candidate.url } }
            .sorted { lhs, rhs in lhs.fetchedAt > rhs.fetchedAt }
        for entry in retained.dropFirst(Self.threadPageMaxEntries) {
            try? fileManager.removeItem(at: entry.url)
        }
        let existingFileNames = Set(threadPageFileURLs().map(\.lastPathComponent))
        let index = loadThreadPageIndex().filter { existingFileNames.contains($0.key) }
        try persistThreadPageIndex(index)
    }

    private func loadThreadPageIndex() -> [String: ThreadPageIndexEntry] {
        guard fileManager.fileExists(atPath: threadPageIndexURL.path),
              let data = try? Data(contentsOf: threadPageIndexURL),
              let envelope = try? decoder.decode(ThreadPageIndexEnvelope.self, from: data),
              envelope.version == Self.schemaVersion else {
            return [:]
        }
        return envelope.pages
    }

    private func persistThreadPageIndex(_ pages: [String: ThreadPageIndexEntry]) throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(ThreadPageIndexEnvelope(version: Self.schemaVersion, pages: pages))
        try data.write(to: threadPageIndexURL, options: [.atomic])
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}

private struct ForumCacheEnvelope<Value: Codable>: Codable {
    var version: Int
    var entry: ForumCacheEntry<Value>
}

private struct ForumCacheEntry<Value: Codable>: Codable {
    var value: Value
    var fetchedAt: Date
}

private struct ThreadPageIndexEnvelope: Codable {
    var version: Int
    var pages: [String: ThreadPageIndexEntry]
}

private struct ThreadPageIndexEntry: Codable {
    var fileName: String
    var threadURL: URL
    var page: Int
    var authorID: String?
    var fetchedAt: Date
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
