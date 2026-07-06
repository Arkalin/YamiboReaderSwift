import Foundation
@preconcurrency import GRDB

public actor MangaReaderProjectionStore: MangaReaderProjectionPersisting {
    public static let projectionNamespace = "manga_reader_projections"

    private let cacheStore: DiskCacheStore
    private nonisolated(unsafe) let fileManager: FileManager

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

    public func projection(for identity: MangaReaderProjectionSourceIdentity) async -> MangaReaderProjection? {
        guard let projection: MangaReaderProjection = try? await cacheStore.get(
            namespace: Self.projectionNamespace,
            key: projectionCacheKey(identity: identity)
        ) else {
            return nil
        }
        return projection
    }

    public func save(_ projection: MangaReaderProjection) async throws {
        try await cacheStore.set(
            projection,
            namespace: Self.projectionNamespace,
            key: projectionCacheKey(identity: projection.sourceIdentity)
        )
    }

    public func clearAll() async throws {
        try await cacheStore.clearNamespace(Self.projectionNamespace)
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

    private func projectionCacheKey(identity: MangaReaderProjectionSourceIdentity) -> String {
        [
            "tid",
            stableKeyComponent(identity.tid),
            "source",
            stableKeyComponent(identity.contentSource.rawValue),
            "author",
            stableKeyComponent(identity.authorID ?? "all"),
            "view",
            String(max(1, identity.view))
        ].joined(separator: "_")
    }

    private func stableKeyComponent(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "empty" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        if normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return normalized
        }
        return stableIdentifier(for: normalized)
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func openDatabase(
        rootDirectory: URL,
        fileManager: FileManager
    ) -> DatabasePool {
        do {
            return try YamiboDatabase.openPool(rootDirectory: rootDirectory, fileManager: fileManager)
        } catch {
            fatalError("Failed to open MangaReaderProjectionStore database: \(error)")
        }
    }
}
