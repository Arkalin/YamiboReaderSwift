import Foundation

public struct NovelReaderProjectionLoadedPage: Sendable {
    public var projection: NovelReaderProjection
    public var sourcePage: ForumThreadPage
    public var source: ReaderProjectionLoadSource

    public init(
        projection: NovelReaderProjection,
        sourcePage: ForumThreadPage,
        source: ReaderProjectionLoadSource
    ) {
        self.projection = projection
        self.sourcePage = sourcePage
        self.source = source
    }
}

public actor NovelReaderProjectionLoader {
    private let loader: ReaderProjectionLoader<NovelProjectionLoadingStrategy>

    public init(
        client: YamiboClient,
        projectionStore: NovelReaderProjectionStore = NovelReaderProjectionStore(),
        forumCacheStore: ForumCacheStore = ForumCacheStore(),
        offlineCacheStore: (any NovelOfflineCacheStoring)? = nil
    ) {
        loader = ReaderProjectionLoader(
            strategy: NovelProjectionLoadingStrategy(
                client: client,
                projectionStore: projectionStore,
                forumCacheStore: forumCacheStore,
                offlineCacheStore: offlineCacheStore
            )
        )
    }

    public func loadProjection(_ request: NovelPageRequest) async throws -> NovelReaderProjectionLoadedPage {
        try await loadProjection(request, ignoresCache: false)
    }

    public func loadProjectionIgnoringCache(_ request: NovelPageRequest) async throws -> NovelReaderProjectionLoadedPage {
        try await loadProjection(request, ignoresCache: true)
    }

    public func loadOnlineProjection(
        _ request: NovelPageRequest,
        ignoresCache: Bool
    ) async throws -> ReaderProjectionPreparedSourcePage<NovelReaderProjection, ForumThreadPage> {
        try await loader.loadOnlineOnly(request, ignoresCache: ignoresCache)
    }

    private func loadProjection(
        _ request: NovelPageRequest,
        ignoresCache: Bool
    ) async throws -> NovelReaderProjectionLoadedPage {
        let loaded = try await loader.load(request, ignoresCache: ignoresCache)
        return NovelReaderProjectionLoadedPage(
            projection: loaded.projection,
            sourcePage: loaded.sourcePage,
            source: loaded.source
        )
    }
}

private struct NovelProjectionIdentity: Hashable, Sendable {
    var threadID: String
    var view: Int
    var authorID: String
}

private struct NovelProjectionLoadingStrategy: ReaderProjectionLoadingStrategy {
    typealias Request = NovelPageRequest
    typealias Identity = NovelProjectionIdentity
    typealias Projection = NovelReaderProjection
    typealias SourcePage = ForumThreadPage

    private static let projectionSchemaVersion = 1

    let client: YamiboClient
    let projectionStore: NovelReaderProjectionStore
    let forumCacheStore: ForumCacheStore
    let offlineCacheStore: (any NovelOfflineCacheStoring)?

    func identity(for request: NovelPageRequest, ignoresCache: Bool) async throws -> NovelProjectionIdentity {
        let thread = ThreadIdentity(tid: request.threadID)
        let authorID = try await resolveAuthorID(for: request, thread: thread, ignoresCache: ignoresCache)
        return NovelProjectionIdentity(threadID: request.threadID, view: request.view, authorID: authorID)
    }

    func onlineSourcePage(
        for request: NovelPageRequest,
        identity: NovelProjectionIdentity,
        ignoresCache: Bool
    ) async throws -> ReaderProjectionSourcePageLoad<ForumThreadPage> {
        try await loadAuthorScopedThreadPage(
            thread: ThreadIdentity(tid: identity.threadID),
            title: nil,
            authorID: identity.authorID,
            view: identity.view,
            ignoresCache: ignoresCache
        )
    }

    func offlineSourcePage(
        for request: NovelPageRequest
    ) async -> ReaderProjectionOfflineSourcePageLoad<NovelProjectionIdentity, ForumThreadPage>? {
        guard let offlineCacheStore else { return nil }
        let normalizedRequestAuthorID = normalizedAuthorID(request.authorID)
        let contentSource: ReaderProjectionContentSource = normalizedRequestAuthorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage
        guard let sourceSnapshot = await offlineCacheStore.novelOfflineSourcePageSnapshot(
            threadID: request.threadID,
            view: request.view,
            authorID: normalizedRequestAuthorID,
            contentSource: contentSource
        ) else {
            return nil
        }
        let effectiveAuthorID = normalizedRequestAuthorID
            ?? sourceSnapshot.sourcePage.posts.first?.author.uid.flatMap { normalizedAuthorID($0) }
        guard let effectiveAuthorID else { return nil }

        return ReaderProjectionOfflineSourcePageLoad(
            sourcePage: sourceSnapshot.sourcePage,
            identity: NovelProjectionIdentity(
                threadID: request.threadID,
                view: request.view,
                authorID: effectiveAuthorID
            ),
            updatedAt: sourceSnapshot.updatedAt
        )
    }

    func fingerprint(sourcePage: ForumThreadPage, identity: NovelProjectionIdentity) -> String {
        Self.projectionFingerprint(
            page: sourcePage,
            threadID: identity.threadID,
            view: identity.view,
            authorID: identity.authorID
        )
    }

    func cachedProjection(for identity: NovelProjectionIdentity) async -> NovelReaderProjection? {
        await projectionStore.loadProjection(
            for: NovelPageRequest(threadID: identity.threadID, view: identity.view, authorID: identity.authorID),
            contentSource: .authorFilteredPage
        )
    }

    func isReusableProjection(
        _ projection: NovelReaderProjection,
        identity: NovelProjectionIdentity,
        fingerprint: String
    ) -> Bool {
        projection.contentSource == .authorFilteredPage &&
            projection.projectionSchemaVersion == Self.projectionSchemaVersion &&
            projection.projectionSourceFingerprint == fingerprint &&
            !isLegacyCachedProjectionMissingChapterCommentSources(projection) &&
            !isCachedProjectionMissingAuthorReplyMetadata(projection)
    }

    func deriveProjection(
        sourcePage: ForumThreadPage,
        identity: NovelProjectionIdentity,
        fingerprint: String
    ) throws -> NovelReaderProjection {
        try NovelReaderProjectionBuilder.build(
            from: sourcePage,
            request: NovelPageRequest(threadID: identity.threadID, view: identity.view, authorID: identity.authorID),
            authorID: identity.authorID,
            projectionSourceFingerprint: fingerprint,
            projectionSchemaVersion: Self.projectionSchemaVersion
        )
    }

    func saveProjection(_ projection: NovelReaderProjection) async throws {
        try await projectionStore.save(projection)
    }

    private func resolveAuthorID(
        for request: NovelPageRequest,
        thread: ThreadIdentity,
        ignoresCache: Bool
    ) async throws -> String {
        if let authorID = normalizedAuthorID(request.authorID) {
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
            if let onlyAuthorID = YamiboThreadHTMLFacts.onlyAuthorID(
                from: html,
                request: NovelPageRequest(threadID: thread.tid, view: 1)
            ) {
                return onlyAuthorID
            }
        }

        if let authorID = discoveryPage.posts.first?.author.uid.flatMap({ normalizedAuthorID($0) }) {
            return authorID
        }
        throw YamiboError.parsingFailed(context: "小说作者范围")
    }

    private func loadAuthorScopedThreadPage(
        thread: ThreadIdentity,
        title: String?,
        authorID: String,
        view: Int,
        ignoresCache: Bool
    ) async throws -> ReaderProjectionSourcePageLoad<ForumThreadPage> {
        if !ignoresCache,
           let cached = await forumCacheStore.loadThreadPage(thread: thread, page: view, authorID: authorID) {
            return ReaderProjectionSourcePageLoad(sourcePage: cached, loadedOnline: false)
        }
        let html = try await fetchThreadHTML(threadID: thread.tid, view: view, authorID: authorID)
        let parsed = try ForumThreadPageHTMLParser.parsePage(from: html, thread: thread, fallbackTitle: title)
        try? await forumCacheStore.saveThreadPage(parsed, thread: thread, pageNumber: view, authorID: authorID)
        return ReaderProjectionSourcePageLoad(sourcePage: parsed, loadedOnline: true)
    }

    private func fetchThreadHTML(threadID: String, view: Int, authorID: String?) async throws -> String {
        do {
            return try await client.fetchThreadById(tid: threadID, authorID: authorID, page: view)
        } catch let error as YamiboError {
            throw error
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw YamiboError.offline
            }
            throw YamiboError.underlying(error.localizedDescription)
        }
    }

    private func isLegacyCachedProjectionMissingChapterCommentSources(_ projection: NovelReaderProjection) -> Bool {
        guard projection.retainedChapterCount > 0, !projection.segments.isEmpty else {
            return false
        }
        return !projection.segmentSources.contains { source in
            source?.ownerPostID?.isEmpty == false
        }
    }

    private func isCachedProjectionMissingAuthorReplyMetadata(_ projection: NovelReaderProjection) -> Bool {
        (projection.decodedSchemaVersion ?? 0) < NovelReaderProjection.schemaVersion
    }

    private func normalizedAuthorID(_ authorID: String?) -> String? {
        let value = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func projectionFingerprint(
        page: ForumThreadPage,
        threadID: String,
        view: Int,
        authorID: String
    ) -> String {
        let value = [
            threadID.trimmingCharacters(in: .whitespacesAndNewlines),
            String(max(1, view)),
            authorID,
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
