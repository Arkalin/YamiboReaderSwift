import Foundation
@preconcurrency import GRDB

public actor NovelReaderProjectionStore {
    public static let projectionNamespace = "novel_reader_projections"

    private let cacheStore: DiskCacheStore
    private nonisolated(unsafe) let fileManager: FileManager
    private let memoryCache = NSCache<NSString, CacheBox>()

    public init(
        databasePool: DatabasePool? = nil,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        baseDirectory: URL? = nil,
        diskCacheStore: DiskCacheStore? = nil
    ) {
        if let diskCacheStore {
            self.cacheStore = diskCacheStore
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
                rootDirectory: resolvedRootDirectory
            )
        }
        self.fileManager = fileManager
    }

    public func loadProjection(
        for request: ReaderPageRequest,
        contentSource: ReaderContentSource? = nil
    ) async -> NovelReaderProjection? {
        let key = projectionCacheKey(threadID: request.threadID, view: request.view, authorID: request.authorID, contentSource: contentSource)

        guard let projection: NovelReaderProjection = try? await cacheStore.get(
            namespace: Self.projectionNamespace,
            key: key
        ) else {
            memoryCache.removeObject(forKey: key as NSString)
            return nil
        }

        memoryCache.setObject(CacheBox(projection: projection), forKey: key as NSString)
        return projection
    }

    public func save(_ projection: NovelReaderProjection) async throws {
        let key = projectionCacheKey(projection: projection)
        try await cacheStore.set(projection, namespace: Self.projectionNamespace, key: key)
        memoryCache.setObject(CacheBox(projection: projection), forKey: key as NSString)
    }

    public func cachedViews(
        for threadID: String,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async -> Set<Int> {
        let identity = ReaderCacheIdentity(threadID: threadID, view: 1, authorID: authorID, contentSource: contentSource)
        let resolvedSource = resolvedContentSource(authorID: authorID, contentSource: contentSource)
        let normalizedAuthorID = authorID?.nilIfBlank
        let entries = (try? await cacheStore.entries(namespace: Self.projectionNamespace)) ?? []
        return Set(entries.compactMap { entry -> Int? in
            guard let parsed = projectionKeyComponents(from: entry.key),
                  parsed.threadID == identity.threadID,
                  parsed.contentSource == resolvedSource,
                  parsed.authorID == normalizedAuthorID else {
                return nil
            }
            return parsed.view
        })
    }

    public func deleteViews(
        _ views: Set<Int>,
        for threadID: String,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async throws {
        for view in views {
            let key = projectionCacheKey(threadID: threadID, view: view, authorID: authorID, contentSource: contentSource)
            try await cacheStore.remove(namespace: Self.projectionNamespace, key: key)
            memoryCache.removeObject(forKey: key as NSString)
        }
    }

    public func deleteAll(
        for threadID: String,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async throws {
        let views = await cachedViews(for: threadID, authorID: authorID, contentSource: contentSource)
        try await deleteViews(views, for: threadID, authorID: authorID, contentSource: contentSource)
    }

    public func totalDiskUsageBytes() async -> Int {
        guard let entries = try? await cacheStore.entries(namespace: Self.projectionNamespace) else {
            return 0
        }
        var total = 0
        for entry in entries {
            guard let fileURL = try? await cacheStore.fileURL(namespace: entry.namespace, key: entry.key),
                  let byteCount = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
                continue
            }
            total += byteCount.intValue
        }
        return total
    }

    public func clearAll() async throws {
        try await cacheStore.clearNamespace(Self.projectionNamespace)
        memoryCache.removeAllObjects()
    }

    private func projectionCacheKey(projection: NovelReaderProjection) -> String {
        projectionCacheKey(
            threadID: projection.threadID,
            view: projection.view,
            authorID: projection.resolvedAuthorID,
            contentSource: projection.contentSource
        )
    }

    private func projectionCacheKey(
        threadID: String,
        view: Int,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) -> String {
        let identity = ReaderCacheIdentity(threadID: threadID, view: view, authorID: authorID, contentSource: contentSource)
        let source = resolvedContentSource(authorID: authorID, contentSource: contentSource)
        return [
            "tid", identity.threadID,
            "source", source.rawValue,
            "author", authorID?.nilIfBlank ?? "all",
            "view", String(identity.view)
        ].joined(separator: "_")
    }

    private func projectionKeyComponents(from key: String) -> ProjectionKeyComponents? {
        let components = key.components(separatedBy: "_")
        guard components.count == 8,
              components[0] == "tid",
              components[2] == "source",
              components[4] == "author",
              components[6] == "view",
              let source = ReaderContentSource(rawValue: components[3]),
              let view = Int(components[7]) else {
            return nil
        }
        let authorID = components[5] == "all" ? nil : components[5]
        return ProjectionKeyComponents(
            threadID: components[1],
            contentSource: source,
            authorID: authorID,
            view: max(1, view)
        )
    }

    private func resolvedContentSource(authorID: String?, contentSource: ReaderContentSource?) -> ReaderContentSource {
        if let contentSource {
            return contentSource
        }
        return authorID?.nilIfBlank == nil ? .fallbackUnfilteredPage : .authorFilteredPage
    }

    private static func openDatabase(
        rootDirectory: URL,
        fileManager: FileManager
    ) -> DatabasePool {
        do {
            return try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory, fileManager: fileManager)
        } catch {
            fatalError("Failed to open NovelReaderProjectionStore database: \(error)")
        }
    }
}

private final class CacheBox: NSObject {
    let projection: NovelReaderProjection

    init(projection: NovelReaderProjection) {
        self.projection = projection
    }
}

private struct ProjectionKeyComponents: Sendable {
    var threadID: String
    var contentSource: ReaderContentSource
    var authorID: String?
    var view: Int
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
