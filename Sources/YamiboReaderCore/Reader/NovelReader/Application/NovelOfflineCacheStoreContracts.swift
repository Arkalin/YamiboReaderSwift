import Foundation

public protocol NovelOfflineImageDataProviding: Sendable {
    func novelOfflineImageData(for imageURL: URL, threadID: String) async -> Data?
}

public protocol NovelOfflineCacheStoring: OfflineCacheUpdateObserving {
    func saveNovelOfflineCacheEntry(_ entry: NovelOfflineCacheEntry) async throws
    func novelOfflineCacheEntry(id: OfflineCacheEntryID) async -> NovelOfflineCacheEntry?
    func allNovelOfflineCacheEntries() async -> [NovelOfflineCacheEntry]
    func saveNovelOfflineSourcePage(
        _ sourcePage: ForumThreadPage,
        request: NovelOfflineCacheWorkRequest,
        updatedAt: Date,
        completesMatchingWork: Bool,
        preservesExistingImageReferencesWhenEmpty: Bool
    ) async throws
    func novelOfflineSourcePage(
        ownerTitle: String,
        threadID: String,
        view: Int,
        authorID: String?,
        contentSource: ReaderProjectionContentSource?
    ) async -> ForumThreadPage?
    func novelOfflineSourcePageSnapshot(
        threadID: String,
        view: Int,
        authorID: String?,
        contentSource: ReaderProjectionContentSource?
    ) async -> NovelOfflineSourcePageSnapshot?
    func novelOfflineCacheViewsSnapshot(
        ownerTitle: String,
        threadID: String,
        authorID: String?,
        contentSource: ReaderProjectionContentSource?
    ) async -> NovelOfflineCacheViewsSnapshot
    func removeNovelOfflineCacheViews(
        _ views: Set<Int>,
        ownerTitle: String,
        threadID: String,
        authorID: String?,
        contentSource: ReaderProjectionContentSource?
    ) async throws
    func enqueueNovelOfflineCacheWork(_ request: NovelOfflineCacheWorkRequest) async throws -> NovelOfflineCacheEnqueueResult
    func enqueueNovelOfflineCacheUpdateWork(_ request: NovelOfflineCacheWorkRequest) async throws -> NovelOfflineCacheEnqueueResult
    func finishNovelOfflineCacheWork(id: OfflineCacheWorkID) async throws
}
