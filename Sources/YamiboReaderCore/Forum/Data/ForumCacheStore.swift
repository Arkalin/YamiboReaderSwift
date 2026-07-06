import Foundation
@preconcurrency import GRDB

public actor ForumCacheStore {
    public static let homeTTL: TimeInterval = 12 * 60 * 60
    public static let boardTTL: TimeInterval = 2 * 60 * 60
    public static let threadPageTTL: TimeInterval = 24 * 60 * 60
    private static let threadPageMaxEntries = 50
    public static let homeNamespace = "forum_home"
    public static let boardNamespace = "forum_boards"
    public static let threadPageNamespace = "forum_thread_pages"
    private static let homeKey = "home"

    private let cacheStore: DiskCacheStore
    private let now: @Sendable () -> Date

    init(
        databasePool: DatabasePool? = nil,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        baseDirectory: URL? = nil,
        diskCacheStore: DiskCacheStore? = nil,
        threadPageDiskCache: DiskCacheStore? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        if let injectedCacheStore = diskCacheStore ?? threadPageDiskCache {
            self.cacheStore = injectedCacheStore
        } else {
            let resolvedRootDirectory = rootDirectory
                ?? baseDirectory
                ?? YamiboDatabase.defaultRootDirectory(fileManager: fileManager)
            let resolvedDatabase = databasePool ?? Self.openDatabase(
                rootDirectory: resolvedRootDirectory,
                fileManager: fileManager
            )
            self.cacheStore = DiskCacheStore(
                writer: resolvedDatabase,
                rootDirectory: resolvedRootDirectory,
                now: now
            )
        }
        self.now = now
    }

    public func loadHome(allowExpired: Bool = false) async -> ForumHomePage? {
        let ttl = allowExpired ? nil : Self.homeTTL
        guard let entry: ForumCacheEntry<ForumHomePage> = try? await cacheStore.get(
            namespace: Self.homeNamespace,
            key: Self.homeKey,
            ttl: ttl
        ) else {
            return nil
        }
        return entry.value
    }

    public func saveHome(_ page: ForumHomePage) async throws {
        try await cacheStore.set(
            ForumCacheEntry(value: page, fetchedAt: page.fetchedAt),
            namespace: Self.homeNamespace,
            key: Self.homeKey
        )
    }

    public func loadBoard(
        fid: String,
        page: Int = 1,
        filterID: String? = nil,
        orderFilter: String? = nil,
        orderBy: String? = nil,
        allowExpired: Bool = false
    ) async -> ForumBoardPage? {
        let ttl = allowExpired ? nil : Self.boardTTL
        guard let entry: ForumCacheEntry<ForumBoardPage> = try? await cacheStore.get(
            namespace: Self.boardNamespace,
            key: boardCacheKey(fid: fid, page: page, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy),
            ttl: ttl
        ) else {
            return nil
        }
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
        try await cacheStore.set(
            ForumCacheEntry(value: page, fetchedAt: page.fetchedAt),
            namespace: Self.boardNamespace,
            key: boardCacheKey(fid: fid, page: pageNumber, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy)
        )
    }

    public func loadThreadPage(
        thread: ThreadIdentity,
        page: Int = 1,
        authorID: String? = nil,
        allowExpired: Bool = false
    ) async -> ForumThreadPage? {
        let ttl = allowExpired ? nil : Self.threadPageTTL
        guard let entry: ForumCacheEntry<ForumThreadPage> = try? await cacheStore.get(
            namespace: Self.threadPageNamespace,
            key: threadPageCacheKey(thread: thread, page: page, authorID: authorID),
            ttl: ttl
        ) else {
            return nil
        }
        return entry.value
    }

    public func cachedThreadPageViews(
        thread: ThreadIdentity,
        authorID: String? = nil,
        allowExpired: Bool = false
    ) async -> Set<Int> {
        let prefix = threadPageCacheKeyPrefix(thread: thread)
        let normalizedAuthorID = authorID?.nilIfBlank
        let entries = (try? await cacheStore.entries(namespace: Self.threadPageNamespace)) ?? []
        return Set(entries.compactMap { entry -> Int? in
            guard entry.key.hasPrefix(prefix),
                  threadPageCacheAuthorID(from: entry.key) == normalizedAuthorID,
                  allowExpired || !isExpired(entry.createdAt, ttl: Self.threadPageTTL) else {
                return nil
            }
            return threadPageCachePage(from: entry.key)
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
        try await cacheStore.set(
            ForumCacheEntry(value: page, fetchedAt: now()),
            namespace: Self.threadPageNamespace,
            key: threadPageCacheKey(thread: thread, page: pageNumber, authorID: authorID)
        )
        try await cacheStore.trimNamespace(Self.threadPageNamespace, maximumEntryCount: Self.threadPageMaxEntries)
    }

    public func clearThreadPages(thread: ThreadIdentity) async throws {
        try await cacheStore.deleteKeys(
            namespace: Self.threadPageNamespace,
            matchingPrefix: threadPageCacheKeyPrefix(thread: thread)
        )
    }

    public func deleteThreadPages(
        _ pages: Set<Int>,
        thread: ThreadIdentity,
        authorID: String?
    ) async throws {
        let normalizedAuthorID = authorID?.nilIfBlank
        let normalizedPages = Set(pages.map { max(1, $0) })
        guard !normalizedPages.isEmpty else { return }
        for page in normalizedPages {
            try await cacheStore.remove(
                namespace: Self.threadPageNamespace,
                key: threadPageCacheKey(thread: thread, page: page, authorID: normalizedAuthorID)
            )
        }
    }

    public func clearAll() async throws {
        try await cacheStore.clearNamespace(Self.homeNamespace)
        try await cacheStore.clearNamespace(Self.boardNamespace)
        try await cacheStore.clearNamespace(Self.threadPageNamespace)
    }

    private func isExpired(_ fetchedAt: Date, ttl: TimeInterval) -> Bool {
        now().timeIntervalSince(fetchedAt) > ttl
    }

    private func boardCacheKey(fid: String, page: Int, filterID: String?, orderFilter: String?, orderBy: String?) -> String {
        let key = [
            fid,
            String(max(1, page)),
            filterID?.nilIfBlank ?? "all",
            orderFilter?.nilIfBlank ?? "default",
            orderBy?.nilIfBlank ?? "default"
        ].joined(separator: "_")
        return "board_\(stableIdentifier(for: key))"
    }

    private func threadPageCacheKey(thread: ThreadIdentity, page: Int, authorID: String?) -> String {
        "\(threadPageCacheKeyPrefix(thread: thread))page_\(max(1, page))_author_\(authorID?.nilIfBlank ?? "all")"
    }

    private func threadPageCacheKeyPrefix(thread: ThreadIdentity) -> String {
        "tid_\(thread.tid)_"
    }

    private func threadPageCachePage(from key: String) -> Int? {
        key.components(separatedBy: "_").enumerated().first { $0.element == "page" }
            .flatMap { index, parts -> Int? in
                let components = key.components(separatedBy: "_")
                guard components.indices.contains(index + 1) else { return nil }
                return Int(components[index + 1])
            }
    }

    private func threadPageCacheAuthorID(from key: String) -> String? {
        let components = key.components(separatedBy: "_")
        guard let index = components.firstIndex(of: "author"),
              components.indices.contains(index + 1) else {
            return nil
        }
        let value = components[index + 1]
        return value == "all" ? nil : value
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func openDatabase(rootDirectory: URL, fileManager: FileManager) -> DatabasePool {
        do {
            return try YamiboDatabase.openPool(rootDirectory: rootDirectory, fileManager: fileManager)
        } catch {
            fatalError("Failed to open ForumCacheStore database: \(error)")
        }
    }
}

private struct ForumCacheEntry<Value: Codable & Sendable>: Codable, Sendable {
    var value: Value
    var fetchedAt: Date
}
