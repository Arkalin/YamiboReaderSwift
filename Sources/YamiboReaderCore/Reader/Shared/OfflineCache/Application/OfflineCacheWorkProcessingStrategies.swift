import Foundation

struct MangaOfflineCachePreparedPayload: Sendable {
    var ownerName: String
    var tid: String
    var chapterTitle: String
    var sourcePage: ForumThreadPage
}

struct MangaOfflineCacheWorkProcessingStrategy: OfflineCacheWorkProcessingStrategy {
    private let readerProjectionLoader: any MangaReaderProjectionSnapshotLoading

    init(readerProjectionLoader: any MangaReaderProjectionSnapshotLoading) {
        self.readerProjectionLoader = readerProjectionLoader
    }

    func prepare(_ work: OfflineCacheProcessingWork) async throws -> OfflineCachePreparedWork<MangaOfflineCachePreparedPayload> {
        guard work.id.readerKind == .manga else {
            throw YamiboError.parsingFailed(context: "Manga Offline Cache")
        }

        let tid = work.entryID.entryKey
        let snapshot = try await readerProjectionLoader.loadReaderProjectionSnapshot(
            MangaReaderProjectionRequest(threadID: tid)
        )
        let targetImageURLs = snapshot.projection.imageURLs
        guard !targetImageURLs.isEmpty else {
            throw YamiboError.parsingFailed(context: "Manga Offline Cache")
        }

        return OfflineCachePreparedWork(
            workID: work.id,
            targetImageURLs: targetImageURLs,
            refererURL: Self.refererURL(for: snapshot.projection.sourceIdentity),
            payload: MangaOfflineCachePreparedPayload(
                ownerName: work.entryID.ownerKey,
                tid: tid,
                chapterTitle: work.title,
                sourcePage: snapshot.sourcePage
            )
        )
    }

    func persistPreparedSource(
        _ preparedWork: OfflineCachePreparedWork<MangaOfflineCachePreparedPayload>,
        in store: any OfflineCacheStoring
    ) async throws {}

    func finish(
        _ preparedWork: OfflineCachePreparedWork<MangaOfflineCachePreparedPayload>,
        in store: any OfflineCacheStoring
    ) async throws {
        let payload = preparedWork.payload
        try await store.saveMembership(
            MangaOfflineCacheMembership(
                ownerName: payload.ownerName,
                tid: payload.tid,
                chapterTitle: payload.chapterTitle,
                imageURLs: preparedWork.targetImageURLs,
                sourcePage: payload.sourcePage
            )
        )
    }

    private static func refererURL(for sourceIdentity: MangaReaderProjectionSourceIdentity) -> URL {
        YamiboRoute.threadByID(
            tid: sourceIdentity.tid,
            page: sourceIdentity.view,
            authorID: sourceIdentity.authorID,
            reverse: false
        ).url
    }
}

struct NovelOfflineCachePreparedPayload: Sendable {
    var sourcePage: ForumThreadPage
    var request: NovelOfflineCacheWorkRequest
}

struct NovelOfflineCacheWorkProcessingStrategy: OfflineCacheWorkProcessingStrategy {
    private let sourcePageLoader: any NovelOfflineCacheSourcePageLoading

    init(sourcePageLoader: any NovelOfflineCacheSourcePageLoading) {
        self.sourcePageLoader = sourcePageLoader
    }

    func prepare(_ work: OfflineCacheProcessingWork) async throws -> OfflineCachePreparedWork<NovelOfflineCachePreparedPayload> {
        let request = try novelWorkRequest(from: work)
        let prepared = try await sourcePageLoader.loadNovelOfflineCacheSourcePage(request)
        let targetImageURLs = work.retainsInlineImages
            ? Self.inlineImageURLs(in: prepared.projection)
            : work.targetImageURLs
        var sourcePageRequest = request
        sourcePageRequest.targetImageURLs = targetImageURLs

        return OfflineCachePreparedWork(
            workID: work.id,
            targetImageURLs: targetImageURLs,
            refererURL: YamiboRoute.threadByID(
                tid: request.threadID,
                page: request.view,
                authorID: request.authorID,
                reverse: false
            ).url,
            payload: NovelOfflineCachePreparedPayload(
                sourcePage: prepared.sourcePage,
                request: sourcePageRequest
            )
        )
    }

    func persistPreparedSource(
        _ preparedWork: OfflineCachePreparedWork<NovelOfflineCachePreparedPayload>,
        in store: any OfflineCacheStoring
    ) async throws {
        let request = preparedWork.payload.request
        try await store.saveNovelOfflineSourcePage(
            preparedWork.payload.sourcePage,
            request: request,
            updatedAt: .now,
            completesMatchingWork: preparedWork.targetImageURLs.isEmpty,
            preservesExistingImageReferencesWhenEmpty: preparedWork.targetImageURLs.isEmpty && !request.retainsInlineImages
        )
    }

    func finish(
        _ preparedWork: OfflineCachePreparedWork<NovelOfflineCachePreparedPayload>,
        in store: any OfflineCacheStoring
    ) async throws {
        guard !preparedWork.targetImageURLs.isEmpty else { return }
        try await store.finishOfflineCacheWork(id: preparedWork.workID)
    }

    private func novelWorkRequest(from work: OfflineCacheProcessingWork) throws -> NovelOfflineCacheWorkRequest {
        guard work.entryID.readerKind == .novel,
              let components = OfflineCacheStore.novelEntryKeyComponents(from: work.entryID.entryKey) else {
            throw YamiboError.parsingFailed(context: "Novel Offline Cache")
        }
        return NovelOfflineCacheWorkRequest(
            ownerTitle: work.ownerTitle,
            title: work.title,
            threadID: components.threadID,
            view: components.view,
            authorID: components.authorID,
            contentSource: components.contentSource,
            targetImageURLs: work.targetImageURLs,
            retainsInlineImages: work.retainsInlineImages
        )
    }

    private static func inlineImageURLs(in projection: NovelReaderProjection) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for segment in projection.segments {
            guard case let .image(url, _) = segment else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }
}
