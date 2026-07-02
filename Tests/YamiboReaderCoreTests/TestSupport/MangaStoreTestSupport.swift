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

func makeTestMangaChapterDocumentStore(
    rootDirectory: URL? = nil,
    prefix: String = "grdb-manga-chapter-document"
) throws -> MangaChapterDocumentStore {
    let rootDirectory = rootDirectory ?? makeTestMangaStoreRoot(prefix: prefix)
    return MangaChapterDocumentStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true))
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

func makeTestFileImageDataCacheStore(
    rootDirectory: URL? = nil,
    baseDirectory: URL? = nil,
    prefix: String = "grdb-image-data-cache",
    diskLimitBytes: Int = FileImageDataCacheStore.defaultDiskLimitBytes
) throws -> FileImageDataCacheStore {
    let rootDirectory = rootDirectory ?? makeTestMangaStoreRoot(prefix: prefix)
    return FileImageDataCacheStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true)),
        baseDirectory: baseDirectory ?? rootDirectory.appendingPathComponent("image-data", isDirectory: true),
        diskLimitBytes: diskLimitBytes
    )
}

func makeTestImageRequest(
    url: URL,
    namespace: YamiboImageCacheNamespace = YamiboImageCacheNamespace(value: "test")
) -> YamiboImageRequest {
    YamiboImageRequest(url: url, cacheNamespace: namespace)
}
