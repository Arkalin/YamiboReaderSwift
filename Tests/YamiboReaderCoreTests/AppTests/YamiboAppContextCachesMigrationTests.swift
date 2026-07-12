import Foundation
import Testing
@testable import YamiboReaderCore

/// Covers the one-time move of purely regenerable file caches (offline-cache,
/// yamibo_cache) out of the iCloud/iTunes-backed Application Support root
/// into the never-backed-up Caches root. Application Support itself keeps
/// `yamibo.sqlite` plus the irreplaceable user content directories
/// (favorite-background, like-images), which this suite does not touch.
@Suite("AppTests: Caches Directory Migration")
struct YamiboAppContextCachesMigrationTests {
    @Test func migratesExistingOfflineCacheAndYamiboCacheDirectoriesOnFirstLaunch() throws {
        let legacyRoot = makeTemporaryDirectory()
        let cachesRoot = makeTemporaryDirectory()
        let fileManager = FileManager.default

        let legacyOfflineFile = legacyRoot
            .appendingPathComponent("offline-cache", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent("legacy-image.bin", isDirectory: false)
        try fileManager.createDirectory(at: legacyOfflineFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy-offline-bytes".utf8).write(to: legacyOfflineFile)

        let legacyCacheFile = legacyRoot
            .appendingPathComponent("yamibo_cache", isDirectory: true)
            .appendingPathComponent("forum_home", isDirectory: true)
            .appendingPathComponent("home.json", isDirectory: false)
        try fileManager.createDirectory(at: legacyCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy-cache-bytes".utf8).write(to: legacyCacheFile)

        _ = YamiboAppContext(grdbRootDirectory: legacyRoot, cachesRootDirectory: cachesRoot)

        let migratedOfflineFile = cachesRoot
            .appendingPathComponent("offline-cache", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent("legacy-image.bin", isDirectory: false)
        let migratedCacheFile = cachesRoot
            .appendingPathComponent("yamibo_cache", isDirectory: true)
            .appendingPathComponent("forum_home", isDirectory: true)
            .appendingPathComponent("home.json", isDirectory: false)

        #expect(fileManager.fileExists(atPath: migratedOfflineFile.path))
        #expect(try Data(contentsOf: migratedOfflineFile) == Data("legacy-offline-bytes".utf8))
        #expect(fileManager.fileExists(atPath: migratedCacheFile.path))
        #expect(try Data(contentsOf: migratedCacheFile) == Data("legacy-cache-bytes".utf8))

        #expect(!fileManager.fileExists(atPath: legacyRoot.appendingPathComponent("offline-cache", isDirectory: true).path))
        #expect(!fileManager.fileExists(atPath: legacyRoot.appendingPathComponent("yamibo_cache", isDirectory: true).path))
    }

    @Test func freshInstallWithNeitherLegacyNorCachesDirectoryStartsUpWithoutError() async throws {
        let legacyRoot = makeTemporaryDirectory()
        let cachesRoot = makeTemporaryDirectory()
        let fileManager = FileManager.default

        #expect(!fileManager.fileExists(atPath: legacyRoot.path))
        #expect(!fileManager.fileExists(atPath: cachesRoot.path))

        let appContext = YamiboAppContext(grdbRootDirectory: legacyRoot, cachesRootDirectory: cachesRoot)

        try await appContext.novelReaderCacheStore.save(
            NovelReaderProjection(
                threadID: "fresh-install",
                view: 1,
                maxView: 1,
                segments: [.text("fresh install cache", chapterTitle: nil)]
            )
        )

        let projectionFile = YamiboDatabase.cacheDirectoryURL(rootDirectory: cachesRoot)
            .appendingPathComponent(NovelReaderProjectionStore.projectionNamespace, isDirectory: true)
        #expect(fileManager.fileExists(atPath: projectionFile.path))
        #expect(!fileManager.fileExists(atPath: legacyRoot.appendingPathComponent("yamibo_cache", isDirectory: true).path))
    }

    @Test func skipsMigrationWhenCachesDestinationAlreadyHasContent() throws {
        let legacyRoot = makeTemporaryDirectory()
        let cachesRoot = makeTemporaryDirectory()
        let fileManager = FileManager.default

        let legacyOfflineFile = legacyRoot
            .appendingPathComponent("offline-cache", isDirectory: true)
            .appendingPathComponent("legacy.bin", isDirectory: false)
        try fileManager.createDirectory(at: legacyOfflineFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy-bytes".utf8).write(to: legacyOfflineFile)

        let existingNewFile = cachesRoot
            .appendingPathComponent("offline-cache", isDirectory: true)
            .appendingPathComponent("already-there.bin", isDirectory: false)
        try fileManager.createDirectory(at: existingNewFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("already-there-bytes".utf8).write(to: existingNewFile)

        _ = YamiboAppContext(grdbRootDirectory: legacyRoot, cachesRootDirectory: cachesRoot)

        #expect(fileManager.fileExists(atPath: legacyOfflineFile.path))
        #expect(fileManager.fileExists(atPath: existingNewFile.path))
        #expect(!fileManager.fileExists(
            atPath: cachesRoot.appendingPathComponent("offline-cache", isDirectory: true).appendingPathComponent("legacy.bin", isDirectory: false).path
        ))
    }

    @Test func favoriteBackgroundAndLikeImagesStayUnderApplicationSupportRoot() {
        let legacyRoot = makeTemporaryDirectory()
        let cachesRoot = makeTemporaryDirectory()

        _ = YamiboAppContext(grdbRootDirectory: legacyRoot, cachesRootDirectory: cachesRoot)

        // These hold user-authored content (custom favorites background photo,
        // retained liked images) that cannot be re-downloaded, so they must
        // remain on the backed-up Application Support root, not move to Caches.
        #expect(!FileManager.default.fileExists(atPath: cachesRoot.appendingPathComponent("favorite-background", isDirectory: true).path))
        #expect(!FileManager.default.fileExists(atPath: cachesRoot.appendingPathComponent("like-images", isDirectory: true).path))
    }
}

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("yamibo-app-context-caches-migration-\(UUID().uuidString)", isDirectory: true)
}
