import Foundation

public actor NovelReaderRepository {
    private static let projectionSchemaVersion = 1

    private let client: YamiboClient
    private let cacheStore: ReaderCacheStore
    private let forumCacheStore: ForumCacheStore
    private let offlineCacheStore: (any OfflineCacheStoring)?
    private let novelOfflineAutoRefreshEnabled: @Sendable () async -> Bool
    private let novelOfflineRetainsInlineImages: @Sendable () async -> Bool

    public init(
        client: YamiboClient,
        cacheStore: ReaderCacheStore = ReaderCacheStore(),
        forumCacheStore: ForumCacheStore = ForumCacheStore(),
        offlineCacheStore: (any OfflineCacheStoring)? = nil,
        novelOfflineAutoRefreshEnabled: @escaping @Sendable () async -> Bool = { true },
        novelOfflineRetainsInlineImages: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.client = client
        self.cacheStore = cacheStore
        self.forumCacheStore = forumCacheStore
        self.offlineCacheStore = offlineCacheStore
        self.novelOfflineAutoRefreshEnabled = novelOfflineAutoRefreshEnabled
        self.novelOfflineRetainsInlineImages = novelOfflineRetainsInlineImages
    }

    public func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        try await loadPageResult(request).document
    }

    public func loadPageResult(_ request: ReaderPageRequest) async throws -> NovelReaderPageLoad {
        try await loadPage(request, ignoresCache: false)
    }

    public func loadPage(threadID: String, view: Int, authorID: String? = nil) async throws -> ReaderPageDocument {
        try await loadPage(ReaderPageRequest(threadID: threadID, view: view, authorID: authorID))
    }

    public func prefetchNextPage(from request: ReaderPageRequest) async {
        let current: ReaderPageDocument
        do {
            current = try await loadPage(request)
        } catch {
            return
        }

        guard current.view < current.maxView else { return }

        let nextRequest = ReaderPageRequest(
            threadURL: request.threadURL,
            view: current.view + 1,
            authorID: current.resolvedAuthorID ?? request.authorID
        )
        _ = try? await loadPage(nextRequest)
    }

    public func cachedViews(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> Set<Int> {
        let projectionViews = await cacheStore.cachedViews(for: threadURL, authorID: authorID, contentSource: contentSource)
        guard (contentSource ?? (normalizedAuthorID(authorID) == nil ? .fallbackUnfilteredPage : .authorFilteredPage)) == .authorFilteredPage,
              let normalizedAuthorID = normalizedAuthorID(authorID),
              let thread = threadIdentity(from: threadURL) else {
            return projectionViews
        }
        let sourceViews = await forumCacheStore.cachedThreadPageViews(thread: thread, authorID: normalizedAuthorID)
        return projectionViews.intersection(sourceViews)
    }

    public func deleteCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        let source = contentSource ?? (normalizedAuthorID(authorID) == nil ? .fallbackUnfilteredPage : .authorFilteredPage)
        try await cacheStore.deleteViews(views, for: threadURL, authorID: authorID, contentSource: source)
        if source == .authorFilteredPage,
           let normalizedAuthorID = normalizedAuthorID(authorID),
           let thread = threadIdentity(from: threadURL) {
            try await forumCacheStore.deleteThreadPages(views, thread: thread, authorID: normalizedAuthorID)
        }
    }

    public func refreshCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        let targets = views.isEmpty
            ? await cachedViews(for: threadURL, authorID: authorID, contentSource: contentSource)
            : views
        try await cacheStore.deleteViews(targets, for: threadURL, authorID: authorID, contentSource: .authorFilteredPage)
        if let authorID = normalizedAuthorID(authorID),
           let thread = threadIdentity(from: threadURL) {
            try await forumCacheStore.deleteThreadPages(targets, thread: thread, authorID: authorID)
        }
        for view in targets.sorted() {
            let request = ReaderPageRequest(threadURL: threadURL, view: view, authorID: authorID)
            _ = try await loadPage(request, ignoresCache: true)
        }
    }

    public func cacheViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?,
        progress: (@Sendable (ReaderCacheBatchProgress) async -> Void)? = nil
    ) async -> ReaderCacheBatchResult {
        let targets = views.sorted()
        guard !targets.isEmpty else {
            let result = ReaderCacheBatchResult(totalCount: 0, completedViews: [], failedViews: [], wasCancelled: false)
            await progress?(ReaderCacheBatchProgress(
                totalCount: 0,
                completedCount: 0,
                currentView: nil,
                completedViews: [],
                failedViews: [],
                status: .completed
            ))
            return result
        }

        var completedViews: [Int] = []
        var failedViews: [Int] = []
        var wasCancelled = false

        for view in targets {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            let request = ReaderPageRequest(threadURL: threadURL, view: view, authorID: authorID)
            do {
                _ = try await loadPageIgnoringCache(request)
                completedViews.append(view)
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
                wasCancelled = true
                break
            } catch {
                failedViews.append(view)
            }

            await progress?(ReaderCacheBatchProgress(
                totalCount: targets.count,
                completedCount: completedViews.count,
                currentView: view,
                completedViews: completedViews,
                failedViews: failedViews,
                status: .running
            ))
        }

        let status: ReaderCacheBatchProgress.Status = wasCancelled ? .cancelled : .completed
        let result = ReaderCacheBatchResult(
            totalCount: targets.count,
            completedViews: completedViews,
            failedViews: failedViews,
            wasCancelled: wasCancelled
        )
        await progress?(ReaderCacheBatchProgress(
            totalCount: targets.count,
            completedCount: completedViews.count,
            currentView: nil,
            completedViews: completedViews,
            failedViews: failedViews,
            status: status
        ))
        return result
    }

    public func loadPageIgnoringCache(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        try await loadPageIgnoringCacheResult(request).document
    }

    public func loadPageIgnoringCacheResult(_ request: ReaderPageRequest) async throws -> NovelReaderPageLoad {
        try await loadPage(request, ignoresCache: true)
    }

    public func loadPageIgnoringCache(threadID: String, view: Int, authorID: String? = nil) async throws -> ReaderPageDocument {
        try await loadPageIgnoringCache(ReaderPageRequest(threadID: threadID, view: view, authorID: authorID))
    }

    public func loadNovelOfflineCacheSourcePage(
        _ request: NovelOfflineCacheWorkRequest
    ) async throws -> NovelOfflineCachePreparedSourcePage {
        let readerRequest = ReaderPageRequest(
            threadURL: request.threadURL,
            view: request.view,
            authorID: request.authorID
        )
        let thread = try requireThreadIdentity(from: request.threadURL)
        let onlinePage = try await loadOnlinePage(readerRequest, thread: thread, ignoresCache: true)
        return NovelOfflineCachePreparedSourcePage(
            sourcePage: onlinePage.sourcePage,
            document: onlinePage.document
        )
    }

    public func fetchThreadDisplayTitle(for threadURL: URL, authorID: String? = nil) async throws -> String {
        let thread = try requireThreadIdentity(from: threadURL)
        return try await fetchThreadDisplayTitle(threadID: thread.tid, authorID: authorID)
    }

    public func fetchThreadDisplayTitle(threadID: String, authorID: String? = nil) async throws -> String {
        let html = try await client.fetchThreadById(tid: threadID, authorID: authorID, page: 1)
        guard let title = ReaderHTMLParser.extractPageTitle(from: html) else {
            throw YamiboError.parsingFailed(context: L10n.string("context.thread_title"))
        }
        return title
    }

    private func loadPage(_ request: ReaderPageRequest, ignoresCache: Bool) async throws -> NovelReaderPageLoad {
        let thread = try requireThreadIdentity(from: request.threadURL)
        do {
            let onlinePage = try await loadOnlinePage(request, thread: thread, ignoresCache: ignoresCache)
            await autoRefreshNovelOfflineCacheIfNeeded(onlinePage)
            return NovelReaderPageLoad(document: onlinePage.document, source: .online)
        } catch {
            guard isEligibleOfflineFallbackTrigger(error),
                  let fallback = await loadOfflineFallback(
                    for: request,
                    thread: thread,
                    authorID: normalizedAuthorID(request.authorID)
                  ) else {
                throw error
            }
            return fallback
        }
    }

    private func loadOnlinePage(
        _ request: ReaderPageRequest,
        thread: ThreadIdentity,
        ignoresCache: Bool
    ) async throws -> OnlineNovelPage {
        let authorID = try await resolveAuthorID(for: request, thread: thread, ignoresCache: ignoresCache)
        let sourceLoad = try await loadAuthorScopedThreadPage(
            thread: thread,
            title: nil,
            authorID: authorID,
            view: request.view,
            ignoresCache: ignoresCache
        )
        let fingerprint = Self.projectionFingerprint(
            page: sourceLoad.page,
            threadURL: thread.canonicalURL,
            view: request.view,
            authorID: authorID
        )
        let projectedRequest = ReaderPageRequest(threadURL: request.threadURL, view: request.view, authorID: authorID)

        if !ignoresCache,
           let cached = await cacheStore.loadDocument(for: projectedRequest, contentSource: .authorFilteredPage),
           isReusableProjection(cached, fingerprint: fingerprint) {
            return OnlineNovelPage(
                document: cached,
                sourcePage: sourceLoad.page,
                thread: thread,
                authorID: authorID,
                sourceLoadedOnline: sourceLoad.loadedOnline
            )
        }

        let document = try ReaderHTMLParser.parseDocument(
            threadPage: sourceLoad.page,
            request: projectedRequest,
            authorID: authorID,
            projectionSourceFingerprint: fingerprint,
            projectionSchemaVersion: Self.projectionSchemaVersion
        )
        try? await cacheStore.save(document)
        return OnlineNovelPage(
            document: document,
            sourcePage: sourceLoad.page,
            thread: thread,
            authorID: authorID,
            sourceLoadedOnline: sourceLoad.loadedOnline
        )
    }

    private func isLegacyCachedDocumentMissingChapterCommentSources(_ document: ReaderPageDocument) -> Bool {
        guard document.retainedChapterCount > 0, !document.segments.isEmpty else {
            return false
        }
        return !document.segmentSources.contains { source in
            source?.ownerPostID?.isEmpty == false
        }
    }

    private func isCachedDocumentMissingAuthorReplyMetadata(_ document: ReaderPageDocument) -> Bool {
        (document.decodedSchemaVersion ?? 0) < ReaderPageDocument.schemaVersion
    }

    private func isReusableProjection(_ document: ReaderPageDocument, fingerprint: String) -> Bool {
        document.contentSource == .authorFilteredPage &&
            document.projectionSchemaVersion == Self.projectionSchemaVersion &&
            document.projectionSourceFingerprint == fingerprint &&
            !isLegacyCachedDocumentMissingChapterCommentSources(document) &&
            !isCachedDocumentMissingAuthorReplyMetadata(document)
    }

    private func resolveAuthorID(
        for request: ReaderPageRequest,
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
            if let onlyAuthorID = ReaderHTMLParser.extractOnlyAuthorID(
                from: html,
                request: ReaderPageRequest(threadURL: thread.canonicalURL, view: 1)
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
    ) async throws -> ThreadPageLoad {
        if !ignoresCache,
           let cached = await forumCacheStore.loadThreadPage(thread: thread, page: view, authorID: authorID) {
            return ThreadPageLoad(page: cached, loadedOnline: false)
        }
        let html = try await fetchThreadHTML(threadID: thread.tid, view: view, authorID: authorID)
        let parsed = try ForumThreadPageHTMLParser.parsePage(from: html, thread: thread, fallbackTitle: title)
        try? await forumCacheStore.saveThreadPage(parsed, thread: thread, pageNumber: view, authorID: authorID)
        return ThreadPageLoad(page: parsed, loadedOnline: true)
    }

    private func fetchThreadHTML(threadID: String, view: Int, authorID: String?) async throws -> String {
        do {
            return try await client.fetchThreadById(tid: threadID, authorID: authorID, page: view)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw YamiboError.offline
            }
            throw YamiboError.underlying(error.localizedDescription)
        }
    }

    private func loadOfflineFallback(
        for request: ReaderPageRequest,
        thread: ThreadIdentity,
        authorID: String?
    ) async -> NovelReaderPageLoad? {
        guard let offlineCacheStore else { return nil }
        let normalizedRequestAuthorID = normalizedAuthorID(authorID)
        let contentSource: ReaderContentSource = normalizedRequestAuthorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage
        guard let sourceSnapshot = await offlineCacheStore.novelOfflineSourcePageSnapshot(
            threadURL: thread.canonicalURL,
            view: request.view,
            authorID: normalizedRequestAuthorID,
            contentSource: contentSource
        ) else {
            return nil
        }
        let effectiveAuthorID = normalizedRequestAuthorID
            ?? sourceSnapshot.sourcePage.posts.first?.author.uid.flatMap { normalizedAuthorID($0) }
        guard let effectiveAuthorID else { return nil }

        let fingerprint = Self.projectionFingerprint(
            page: sourceSnapshot.sourcePage,
            threadURL: thread.canonicalURL,
            view: request.view,
            authorID: effectiveAuthorID
        )
        let projectedRequest = ReaderPageRequest(
            threadURL: request.threadURL,
            view: request.view,
            authorID: effectiveAuthorID
        )
        if let prewarm = await offlineCacheStore.novelOfflineProjectionPrewarm(
            ownerTitle: sourceSnapshot.ownerTitle,
            threadURL: thread.canonicalURL,
            view: request.view,
            authorID: effectiveAuthorID,
            contentSource: .authorFilteredPage
        ),
            isReusableProjection(prewarm, fingerprint: fingerprint) {
            return NovelReaderPageLoad(
                document: prewarm,
                source: .offlineFallback(updatedAt: sourceSnapshot.updatedAt)
            )
        }

        guard let document = try? ReaderHTMLParser.parseDocument(
            threadPage: sourceSnapshot.sourcePage,
            request: projectedRequest,
            authorID: effectiveAuthorID,
            projectionSourceFingerprint: fingerprint,
            projectionSchemaVersion: Self.projectionSchemaVersion
        ) else {
            return nil
        }
        try? await offlineCacheStore.saveNovelOfflineProjectionPrewarm(
            document,
            ownerTitle: sourceSnapshot.ownerTitle
        )
        return NovelReaderPageLoad(
            document: document,
            source: .offlineFallback(updatedAt: sourceSnapshot.updatedAt)
        )
    }

    private func autoRefreshNovelOfflineCacheIfNeeded(_ onlinePage: OnlineNovelPage) async {
        guard onlinePage.sourceLoadedOnline,
              let offlineCacheStore,
              await novelOfflineAutoRefreshEnabled() else {
            return
        }
        guard let existing = await offlineCacheStore.novelOfflineSourcePageSnapshot(
            threadURL: onlinePage.thread.canonicalURL,
            view: onlinePage.document.view,
            authorID: onlinePage.authorID,
            contentSource: .authorFilteredPage
        ) else {
            return
        }
        let retainsInlineImages = await novelOfflineRetainsInlineImages()
        let targetImageURLs = retainsInlineImages ? Self.inlineImageURLs(in: onlinePage.document) : []
        let request = NovelOfflineCacheWorkRequest(
            ownerTitle: existing.ownerTitle,
            title: NovelOfflineCacheEntry.defaultTitle(document: onlinePage.document),
            threadURL: onlinePage.thread.canonicalURL,
            view: onlinePage.document.view,
            authorID: onlinePage.authorID,
            contentSource: .authorFilteredPage,
            targetImageURLs: targetImageURLs,
            retainsInlineImages: retainsInlineImages
        )
        try? await offlineCacheStore.saveNovelOfflineSourcePage(
            onlinePage.sourcePage,
            request: request,
            projectionPrewarm: onlinePage.document,
            updatedAt: .now,
            completesMatchingWork: targetImageURLs.isEmpty,
            preservesExistingImageReferencesWhenEmpty: !retainsInlineImages
        )
        guard retainsInlineImages, !targetImageURLs.isEmpty else { return }
        _ = try? await offlineCacheStore.enqueueNovelOfflineCacheUpdateWork(request)
    }

    private func isEligibleOfflineFallbackTrigger(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        guard let yamiboError = error as? YamiboError else {
            return false
        }
        switch yamiboError {
        case .offline, .underlying, .invalidResponse, .unreadableBody, .emptyHTML:
            return true
        case .parsingFailed,
             .floodControl,
             .notAuthenticated,
             .accountUIDUnavailable,
             .loginFormUnavailable,
             .loginFailed,
             .loginVerificationRequired,
             .searchCooldown,
             .persistenceFailed,
             .missingFavoriteDeleteToken,
             .missingFavoriteDeleteID,
             .favoriteDeleteFailed,
             .missingFavoriteAddToken,
             .missingFavoriteThreadID,
             .favoriteAddFailed,
             .missingForumBoardFavoriteToken,
             .forumBoardFavoriteFailed,
             .missingForumSearchToken:
            return false
        }
    }

    private static func inlineImageURLs(in document: ReaderPageDocument) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for segment in document.segments {
            guard case let .image(url, _) = segment else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func requireThreadIdentity(from threadURL: URL) throws -> ThreadIdentity {
        guard let thread = threadIdentity(from: threadURL) else {
            throw YamiboError.parsingFailed(context: L10n.string("context.thread_page"))
        }
        return thread
    }

    private func threadIdentity(from threadURL: URL) -> ThreadIdentity? {
        let canonicalURL = ReaderCacheIdentity.canonicalThreadURL(from: threadURL)
        guard let tid = ReaderHTMLParser.extractThreadID(from: canonicalURL) else { return nil }
        return ThreadIdentity(tid: tid, canonicalURL: canonicalURL)
    }

    private func normalizedAuthorID(_ authorID: String?) -> String? {
        let value = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func projectionFingerprint(
        page: ForumThreadPage,
        threadURL: URL,
        view: Int,
        authorID: String
    ) -> String {
        let value = [
            threadURL.absoluteString,
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

extension NovelReaderRepository: NovelOfflineCacheSourcePageLoading {}

private struct ThreadPageLoad: Sendable {
    var page: ForumThreadPage
    var loadedOnline: Bool
}

private struct OnlineNovelPage: Sendable {
    var document: ReaderPageDocument
    var sourcePage: ForumThreadPage
    var thread: ThreadIdentity
    var authorID: String
    var sourceLoadedOnline: Bool
}
