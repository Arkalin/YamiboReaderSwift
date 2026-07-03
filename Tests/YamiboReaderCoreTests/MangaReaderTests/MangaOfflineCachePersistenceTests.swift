import Foundation
@preconcurrency import GRDB
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Persistence")
struct MangaReaderTestsMangaOfflineCachePersistence {
    @Test func appContextDefaultsUseMangaOfflineCacheStore() {
        let appContext = YamiboAppContext()

        #expect(appContext.mangaOfflineCacheStore is MangaOfflineCacheStore)
    }

    @Test func membershipWorkAndProgressSurviveRestartWithoutChapterURLColumns() async throws {
        let fixture = try makeOfflineCacheFixture()
        let firstStore = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )
        let imageURLs = try makeOfflineImageURLs(tid: "100", count: 2)

        try await firstStore.saveMembership(
            try makeOfflineMembership(ownerName: "作品A", tid: "100", imageURLs: imageURLs)
        )
        _ = try await firstStore.enqueueOfflineCacheWork(
            try makeOfflineWorkRequest(ownerName: "作品A", tid: "101", targetImageURLs: imageURLs)
        )
        try await firstStore.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "101",
            targetImageURLs: imageURLs,
            completedImageURLs: [imageURLs[0]],
            currentBytesPerSecond: 256
        )

        let secondStore = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )
        let membership = try #require(await secondStore.membership(ownerName: "作品A", tid: "100"))
        let work = try #require(await secondStore.offlineCacheWork(ownerName: "作品A", tid: "101"))

        #expect(membership.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=100")
        #expect(membership.imageURLs == imageURLs)
        #expect(work.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=101")
        #expect(work.completedImageURLs == [imageURLs[0]])
        #expect(work.progress == MangaOfflineCacheProgress(completedImageCount: 1, targetImageCount: 2))

        let databaseState = try await fixture.database.read { db in
            (
                membershipColumns: try offlineCacheColumnNames(table: "manga_offline_cache_memberships", in: db),
                workColumns: try offlineCacheColumnNames(table: "manga_offline_cache_works", in: db),
                persistedMetadataText: try String.fetchAll(
                    db,
                    sql: """
                    SELECT owner_name FROM manga_offline_cache_memberships
                    UNION ALL SELECT tid FROM manga_offline_cache_memberships
                    UNION ALL SELECT chapter_title FROM manga_offline_cache_memberships
                    UNION ALL SELECT owner_name FROM manga_offline_cache_works
                    UNION ALL SELECT tid FROM manga_offline_cache_works
                    UNION ALL SELECT chapter_title FROM manga_offline_cache_works
                    UNION ALL SELECT state FROM manga_offline_cache_works
                    """
                )
            )
        }

        #expect(!databaseState.membershipColumns.contains("chapter_url"))
        #expect(!databaseState.workColumns.contains("chapter_url"))
        #expect(databaseState.persistedMetadataText.allSatisfy { !$0.contains("forum.php") })
    }

    @Test func offlineImageBytesStayInFilesWhileMetadataLivesInGRDB() async throws {
        let fixture = try makeOfflineCacheFixture()
        let store = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )
        let imageURL = try #require(URL(string: "https://img.example.com/file-backed.jpg"))

        try await store.saveOfflineImageData(Data([1, 2, 3, 4]), for: imageURL)

        #expect(await store.offlineImageData(for: imageURL) == Data([1, 2, 3, 4]))
        #expect(await store.totalDiskUsageBytes() == 4)

        let imageRows: [(imageURL: String, fileName: String, byteCount: Int)] = try await fixture.database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT image_url, file_name, byte_count FROM manga_offline_cache_images"
            ).map { row in
                (
                    imageURL: row["image_url"] as String,
                    fileName: row["file_name"] as String,
                    byteCount: row["byte_count"] as Int
                )
            }
        }
        let row = try #require(imageRows.first)
        let fileURL = fixture.offlineDirectory
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(row.fileName, isDirectory: false)

        #expect(row.imageURL == imageURL.absoluteString)
        #expect(row.byteCount == 4)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func restartRecoveryPausesRunningQueueAndKeepsFailedWork() async throws {
        let fixture = try makeOfflineCacheFixture()
        let writingStore = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )
        let imageURL = try #require(URL(string: "https://img.example.com/restart.jpg"))

        _ = try await writingStore.enqueueOfflineCacheWork(
            try makeOfflineWorkRequest(ownerName: "作品A", tid: "200", targetImageURLs: [imageURL])
        )
        try await writingStore.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "200",
            targetImageURLs: [imageURL],
            completedImageURLs: [imageURL],
            currentBytesPerSecond: 512
        )
        try await writingStore.markOfflineCacheWorkFailed(ownerName: "作品A", tid: "200", message: "Timeout")
        try await writingStore.setOfflineCacheQueueRunState(.running)

        let recoveredStore = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )

        #expect(await recoveredStore.offlineCacheQueueRunState() == .paused)
        let recoveredWork = try #require(await recoveredStore.offlineCacheWork(ownerName: "作品A", tid: "200"))
        #expect(recoveredWork.state == .failed)
        #expect(recoveredWork.failureMessage == "Timeout")
        #expect(recoveredWork.currentBytesPerSecond == 0)
    }

    @Test func cancelDeleteAndUsageDeriveFromGRDBMetadataPlusFileAvailability() async throws {
        let fixture = try makeOfflineCacheFixture()
        let store = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )
        let sharedImage = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let removedImage = try #require(URL(string: "https://img.example.com/removed.jpg"))

        try await store.saveOfflineImageData(Data([1, 2, 3]), for: sharedImage)
        try await store.saveOfflineImageData(Data([4, 5]), for: removedImage)
        try await store.saveMembership(
            try makeOfflineMembership(ownerName: "作品A", tid: "300", imageURLs: [sharedImage, removedImage])
        )
        try await store.saveMembership(
            try makeOfflineMembership(ownerName: "作品A", tid: "301", imageURLs: [sharedImage])
        )

        #expect(await store.offlineCacheState(ownerName: "作品A", tid: "300") == .cached)

        try await store.removeMembership(ownerName: "作品A", tid: "300")

        #expect(await store.membership(ownerName: "作品A", tid: "300") == nil)
        #expect(await store.offlineImageData(for: sharedImage) == Data([1, 2, 3]))
        #expect(await store.offlineImageData(for: removedImage) == nil)
        #expect(await store.diskUsageByOwner() == [
            MangaOfflineCacheOwnerUsage(ownerName: "作品A", byteCount: 3)
        ])
    }

    @Test func queueExecutorProcessesGRDBBackedWorkAndRemovesCompletedQueueRows() async throws {
        let fixture = try makeOfflineCacheFixture()
        let store = MangaOfflineCacheStore(
            databasePool: fixture.database,
            baseDirectory: fixture.offlineDirectory
        )
        let imageURLs = try makeOfflineImageURLs(tid: "400", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeOfflineWorkRequest(ownerName: "作品A", tid: "400", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            imageAcquirer: acquirer,
            maxConcurrentImageTransfers: 1
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheWork(ownerName: "作品A", tid: "400") == nil)
        #expect(await store.offlineCacheState(ownerName: "作品A", tid: "400") == .cached)
        #expect(await store.membership(ownerName: "作品A", tid: "400")?.imageURLs == imageURLs)
        #expect(await acquirer.requestedURLs == imageURLs)
    }
}

private struct OfflineCacheFixture {
    let database: DatabasePool
    let offlineDirectory: URL
}

private func makeOfflineCacheFixture() throws -> OfflineCacheFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("grdb-offline-cache-\(UUID().uuidString)", isDirectory: true)
    return OfflineCacheFixture(
        database: try YamiboDatabase.openPool(rootDirectory: root),
        offlineDirectory: root.appendingPathComponent("offline-images", isDirectory: true)
    )
}

private func makeOfflineMembership(
    ownerName: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        imageURLs: imageURLs
    )
}

private func makeOfflineWorkRequest(
    ownerName: String,
    tid: String,
    targetImageURLs: [URL]
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        targetImageURLs: targetImageURLs
    )
}

private func makeOfflineImageURLs(tid: String, count: Int) throws -> [URL] {
    try (1...count).map { index in
        try #require(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
    }
}

private func offlineCacheColumnNames(table: String, in db: Database) throws -> [String] {
    try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String }
}

private actor RecordingOfflineImageAcquirer: MangaOfflineCacheImageAcquiring {
    private(set) var requestedURLs: [URL] = []
    private var dataByURL: [URL: Data] = [:]

    func setData(for imageURLs: [URL]) {
        for (index, imageURL) in imageURLs.enumerated() {
            dataByURL[imageURL] = Data([UInt8(index + 1)])
        }
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition {
        requestedURLs.append(imageURL)
        guard let data = dataByURL[imageURL] else {
            throw YamiboError.invalidResponse(statusCode: 404)
        }
        return MangaOfflineCacheImageAcquisition(data: data, source: .network)
    }
}

private actor RecordingReaderProjectionLoader: MangaReaderProjectionLoading {
    func loadReaderProjection(at url: URL) async throws -> MangaReaderProjection {
        throw YamiboError.parsingFailed(context: "Unexpected document load in offline-cache test")
    }
}
