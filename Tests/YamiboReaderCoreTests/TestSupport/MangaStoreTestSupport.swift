import Foundation
@preconcurrency import GRDB
@testable import YamiboReaderCore

func makeTestMangaStoreRoot(prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

func makeTestMangaDirectoryStore(
    rootDirectory: URL? = nil,
    prefix: String = "grdb-manga-directory"
) throws -> MangaDirectoryStore {
    let rootDirectory = rootDirectory ?? makeTestMangaStoreRoot(prefix: prefix)
    return MangaDirectoryStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true))
    )
}

func makeTestMangaReaderProjectionStore(
    rootDirectory: URL? = nil,
    prefix: String = "grdb-manga-reader-projection"
) throws -> MangaReaderProjectionStore {
    let rootDirectory = rootDirectory ?? makeTestMangaStoreRoot(prefix: prefix)
    return MangaReaderProjectionStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true)),
        rootDirectory: rootDirectory
    )
}

func makeTestMangaOfflineCacheStore(
    rootDirectory: URL? = nil,
    baseDirectory: URL? = nil,
    prefix: String = "grdb-manga-offline-cache"
) throws -> MangaOfflineCacheStore {
    let rootDirectory = rootDirectory ?? makeTestMangaStoreRoot(prefix: prefix)
    return MangaOfflineCacheStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true)),
        baseDirectory: baseDirectory ?? rootDirectory.appendingPathComponent("offline-images", isDirectory: true)
    )
}
