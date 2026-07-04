import Foundation

public actor MangaReaderProjectionLoader: MangaReaderProjectionSnapshotLoading {
    private let loader: ReaderProjectionLoader<MangaProjectionLoadingStrategy>

    public init(
        client: YamiboClient,
        projectionStore: any MangaReaderProjectionPersisting,
        forumCacheStore: ForumCacheStore,
        offlineCacheStore: (any OfflineCacheStoring)? = nil
    ) {
        loader = ReaderProjectionLoader(
            strategy: MangaProjectionLoadingStrategy(
                client: client,
                projectionStore: projectionStore,
                forumCacheStore: forumCacheStore,
                offlineCacheStore: offlineCacheStore
            ),
            coalescesInFlightRequests: true
        )
    }

    public func loadReaderProjection(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjection {
        try await loadReaderProjectionSnapshot(request).projection
    }

    public func loadReaderProjectionSnapshot(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjectionSnapshot {
        let loaded = try await loader.load(request, ignoresCache: false)
        return MangaReaderProjectionSnapshot(projection: loaded.projection, sourcePage: loaded.sourcePage)
    }

    public func loadReaderProjectionIgnoringCache(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjection {
        try await loader.load(request, ignoresCache: true).projection
    }
}

private struct MangaProjectionLoadingStrategy: ReaderProjectionLoadingStrategy {
    typealias Request = MangaReaderProjectionRequest
    typealias Identity = MangaReaderProjectionSourceIdentity
    typealias Projection = MangaReaderProjection
    typealias SourcePage = ForumThreadPage

    let client: YamiboClient
    let projectionStore: any MangaReaderProjectionPersisting
    let forumCacheStore: ForumCacheStore
    let offlineCacheStore: (any OfflineCacheStoring)?

    func identity(for request: MangaReaderProjectionRequest, ignoresCache: Bool) async throws -> MangaReaderProjectionSourceIdentity {
        let thread = ThreadIdentity(tid: request.threadID)
        let authorID = try await resolveAuthorID(
            requestedAuthorID: request.authorID,
            thread: thread,
            ignoresCache: ignoresCache
        )
        return MangaReaderProjectionSourceIdentity(
            tid: request.threadID,
            authorID: authorID,
            contentSource: .authorFilteredPage,
            view: request.view
        )
    }

    func onlineSourcePage(
        for request: MangaReaderProjectionRequest,
        identity: MangaReaderProjectionSourceIdentity,
        ignoresCache: Bool
    ) async throws -> ReaderProjectionSourcePageLoad<ForumThreadPage> {
        let sourcePage = try await loadAuthorScopedThreadPage(
            thread: ThreadIdentity(tid: request.threadID),
            authorID: identity.authorID ?? "",
            view: request.view,
            ignoresCache: ignoresCache
        )
        return ReaderProjectionSourcePageLoad(sourcePage: sourcePage, loadedOnline: true)
    }

    func offlineSourcePage(
        for request: MangaReaderProjectionRequest
    ) async -> ReaderProjectionOfflineSourcePageLoad<MangaReaderProjectionSourceIdentity, ForumThreadPage>? {
        guard let offlineCacheStore,
              let ownerName = request.offlineOwnerName?.mangaReaderTrimmedNonEmpty,
              let membership = await offlineCacheStore.membership(ownerName: ownerName, tid: request.threadID),
              membership.tid == request.threadID,
              membership.sourcePage.thread.tid == request.threadID,
              sourcePageMatchesRequestedView(membership.sourcePage, view: request.view) else {
            return nil
        }

        let authorID = request.authorID?.mangaReaderTrimmedNonEmpty
            ?? membership.sourcePage.posts.first?.author.uid?.mangaReaderTrimmedNonEmpty
        guard let authorID else { return nil }

        let identity = MangaReaderProjectionSourceIdentity(
            tid: request.threadID,
            authorID: authorID,
            contentSource: .authorFilteredPage,
            view: request.view
        )
        return ReaderProjectionOfflineSourcePageLoad(
            sourcePage: membership.sourcePage,
            identity: identity,
            updatedAt: nil
        )
    }

    func fingerprint(sourcePage: ForumThreadPage, identity: MangaReaderProjectionSourceIdentity) -> String {
        Self.projectionFingerprint(page: sourcePage, identity: identity)
    }

    func cachedProjection(for identity: MangaReaderProjectionSourceIdentity) async -> MangaReaderProjection? {
        await projectionStore.projection(for: identity)
    }

    func isReusableProjection(
        _ projection: MangaReaderProjection,
        identity: MangaReaderProjectionSourceIdentity,
        fingerprint: String
    ) -> Bool {
        projection.sourceIdentity == identity &&
            projection.sourceFingerprint == fingerprint &&
            projection.schemaVersion == MangaReaderProjection.schemaVersion &&
            projection.parserVersion == MangaReaderProjection.parserVersion &&
            !projection.imageURLs.isEmpty
    }

    func deriveProjection(
        sourcePage: ForumThreadPage,
        identity: MangaReaderProjectionSourceIdentity,
        fingerprint: String
    ) throws -> MangaReaderProjection {
        guard identity.contentSource == .authorFilteredPage,
              identity.authorID?.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.parsingFailed(context: "漫画作者范围")
        }
        let imageURLs = Self.orderedImageURLs(from: sourcePage)
        guard !imageURLs.isEmpty else {
            throw MangaReaderDataSupport.currentMangaChapterParsingFailure()
        }
        let ownerPost = sourcePage.posts.first
        let rawTitle = sourcePage.title.mangaReaderTrimmedNonEmpty ?? identity.tid
        let chapterTitle = MangaTitleCleaner.cleanThreadTitle(rawTitle).mangaReaderTrimmedNonEmpty
            ?? rawTitle

        return MangaReaderProjection(
            tid: identity.tid,
            ownerPostID: ownerPost?.postID,
            ownerAuthorID: identity.authorID,
            ownerAuthorName: ownerPost?.author.name,
            chapterTitle: chapterTitle,
            imageURLs: imageURLs,
            sourceIdentity: identity,
            sourceFingerprint: fingerprint,
            schemaVersion: MangaReaderProjection.schemaVersion,
            parserVersion: MangaReaderProjection.parserVersion
        )
    }

    func saveProjection(_ projection: MangaReaderProjection) async throws {
        try await projectionStore.save(projection)
    }

    private func resolveAuthorID(
        requestedAuthorID: String?,
        thread: ThreadIdentity,
        ignoresCache: Bool
    ) async throws -> String {
        if let authorID = requestedAuthorID?.mangaReaderTrimmedNonEmpty {
            return authorID
        }

        let discoveryPage: ForumThreadPage
        if !ignoresCache,
           let cached = await forumCacheStore.loadThreadPage(thread: thread, page: 1, authorID: nil) {
            discoveryPage = cached
        } else {
            let html = try await fetchThreadHTML(threadID: thread.tid, view: 1, authorID: nil)
            discoveryPage = try ForumThreadPageHTMLParser.parsePage(
                from: html,
                thread: thread,
                fallbackTitle: nil
            )
            try? await forumCacheStore.saveThreadPage(discoveryPage, thread: thread, pageNumber: 1, authorID: nil)
            if let onlyAuthorID = ReaderHTMLParser.extractOnlyAuthorID(
                from: html,
                request: ReaderPageRequest(threadID: thread.tid, view: 1)
            )?.mangaReaderTrimmedNonEmpty {
                return onlyAuthorID
            }
        }

        if let authorID = discoveryPage.posts.first?.author.uid?.mangaReaderTrimmedNonEmpty {
            return authorID
        }
        throw YamiboError.parsingFailed(context: "漫画作者范围")
    }

    private func loadAuthorScopedThreadPage(
        thread: ThreadIdentity,
        authorID: String,
        view: Int,
        ignoresCache: Bool
    ) async throws -> ForumThreadPage {
        if !ignoresCache,
           let cached = await forumCacheStore.loadThreadPage(thread: thread, page: view, authorID: authorID) {
            return cached
        }
        let html = try await fetchThreadHTML(threadID: thread.tid, view: view, authorID: authorID)
        let parsed = try ForumThreadPageHTMLParser.parsePage(from: html, thread: thread, fallbackTitle: nil)
        try? await forumCacheStore.saveThreadPage(parsed, thread: thread, pageNumber: view, authorID: authorID)
        return parsed
    }

    private func fetchThreadHTML(threadID: String, view: Int, authorID: String?) async throws -> String {
        do {
            return try await client.fetchThreadById(tid: threadID, authorID: authorID, page: view)
        } catch let error as YamiboError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw YamiboError.offline
            default:
                throw YamiboError.underlying(error.localizedDescription)
            }
        }
    }

    private func sourcePageMatchesRequestedView(_ sourcePage: ForumThreadPage, view: Int) -> Bool {
        guard let currentPage = sourcePage.pageNavigation?.currentPage else { return true }
        return currentPage == max(1, view)
    }

    private static func orderedImageURLs(from page: ForumThreadPage) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        let baseURL = YamiboRoute.threadByID(
            tid: page.thread.tid,
            page: page.pageNavigation?.currentPage ?? 1,
            authorID: nil,
            reverse: false
        ).url
        for post in page.posts {
            for image in post.images {
                guard let url = HTMLTextExtractor.absoluteURL(from: image.url, baseURL: baseURL) else {
                    continue
                }
                if seen.insert(url.absoluteString).inserted {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private static func projectionFingerprint(
        page: ForumThreadPage,
        identity: MangaReaderProjectionSourceIdentity
    ) -> String {
        let value = [
            identity.tid,
            identity.authorID ?? "",
            identity.contentSource.rawValue,
            String(identity.view),
            page.posts.map { post in
                [
                    post.postID,
                    post.author.uid ?? "",
                    post.contentHTML,
                    post.images.map(\.url).joined(separator: ",")
                ].joined(separator: "\u{1E}")
            }.joined(separator: "\u{1D}"),
            String(page.pageNavigation?.totalPages ?? 0)
        ].joined(separator: "\u{1F}")
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}
