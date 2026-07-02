import Foundation
@preconcurrency import GRDB
@testable import YamiboReaderCore

func makeTestGRDBMangaRoot(prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

func makeTestGRDBMangaDirectoryStore(
    rootDirectory: URL? = nil,
    prefix: String = "grdb-manga-directory"
) throws -> GRDBMangaDirectoryStore {
    let rootDirectory = rootDirectory ?? makeTestGRDBMangaRoot(prefix: prefix)
    return GRDBMangaDirectoryStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true))
    )
}

func makeTestGRDBMangaChapterDocumentStore(
    rootDirectory: URL? = nil,
    prefix: String = "grdb-manga-chapter-document"
) throws -> GRDBMangaChapterDocumentStore {
    let rootDirectory = rootDirectory ?? makeTestGRDBMangaRoot(prefix: prefix)
    return GRDBMangaChapterDocumentStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true))
    )
}

func makeTestGRDBMangaOfflineCacheStore(
    rootDirectory: URL? = nil,
    baseDirectory: URL? = nil,
    prefix: String = "grdb-manga-offline-cache"
) throws -> GRDBMangaOfflineCacheStore {
    let rootDirectory = rootDirectory ?? makeTestGRDBMangaRoot(prefix: prefix)
    return GRDBMangaOfflineCacheStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true)),
        baseDirectory: baseDirectory ?? rootDirectory.appendingPathComponent("offline-images", isDirectory: true)
    )
}

func makeTestFileMangaImageDataCacheStore(
    rootDirectory: URL? = nil,
    baseDirectory: URL? = nil,
    prefix: String = "grdb-manga-image-data-cache",
    diskLimitBytes: Int = FileMangaImageDataCacheStore.defaultDiskLimitBytes
) throws -> FileMangaImageDataCacheStore {
    let rootDirectory = rootDirectory ?? makeTestGRDBMangaRoot(prefix: prefix)
    return FileMangaImageDataCacheStore(
        databasePool: try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory.appendingPathComponent("grdb", isDirectory: true)),
        baseDirectory: baseDirectory ?? rootDirectory.appendingPathComponent("transparent-images", isDirectory: true),
        diskLimitBytes: diskLimitBytes
    )
}

func makeTestFileImageDataCacheStore(
    rootDirectory: URL? = nil,
    baseDirectory: URL? = nil,
    prefix: String = "grdb-image-data-cache",
    diskLimitBytes: Int = FileImageDataCacheStore.defaultDiskLimitBytes
) throws -> FileImageDataCacheStore {
    let rootDirectory = rootDirectory ?? makeTestGRDBMangaRoot(prefix: prefix)
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
