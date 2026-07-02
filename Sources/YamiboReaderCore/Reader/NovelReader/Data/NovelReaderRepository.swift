import Foundation

public actor NovelReaderRepository {
    private static let projectionSchemaVersion = 1

    private let client: YamiboClient
    private let cacheStore: ReaderCacheStore
    private let forumCacheStore: ForumCacheStore

    public init(
        client: YamiboClient,
        cacheStore: ReaderCacheStore = ReaderCacheStore(),
        forumCacheStore: ForumCacheStore = ForumCacheStore()
    ) {
        self.client = client
        self.cacheStore = cacheStore
        self.forumCacheStore = forumCacheStore
    }

    public func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
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
        try await loadPage(request, ignoresCache: true)
    }

    public func loadPageIgnoringCache(threadID: String, view: Int, authorID: String? = nil) async throws -> ReaderPageDocument {
        try await loadPageIgnoringCache(ReaderPageRequest(threadID: threadID, view: view, authorID: authorID))
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

    private func loadPage(_ request: ReaderPageRequest, ignoresCache: Bool) async throws -> ReaderPageDocument {
        let thread = try requireThreadIdentity(from: request.threadURL)
        let authorID = try await resolveAuthorID(for: request, thread: thread, ignoresCache: ignoresCache)
        let sourcePage = try await loadAuthorScopedThreadPage(
            thread: thread,
            title: nil,
            authorID: authorID,
            view: request.view,
            ignoresCache: ignoresCache
        )
        let fingerprint = Self.projectionFingerprint(
            page: sourcePage,
            threadURL: thread.canonicalURL,
            view: request.view,
            authorID: authorID
        )
        let projectedRequest = ReaderPageRequest(threadURL: request.threadURL, view: request.view, authorID: authorID)

        if !ignoresCache,
           let cached = await cacheStore.loadDocument(for: projectedRequest, contentSource: .authorFilteredPage),
           isReusableProjection(cached, fingerprint: fingerprint) {
            return cached
        }

        let document = try ReaderHTMLParser.parseDocument(
            threadPage: sourcePage,
            request: projectedRequest,
            authorID: authorID,
            projectionSourceFingerprint: fingerprint,
            projectionSchemaVersion: Self.projectionSchemaVersion
        )
        try? await cacheStore.save(document)
        return document
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

        if let authorID = discoveryPage.posts.first?.author.uid.flatMap(normalizedAuthorID) {
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
    ) async throws -> ForumThreadPage {
        if !ignoresCache,
           let cached = await forumCacheStore.loadThreadPage(thread: thread, page: view, authorID: authorID) {
            return cached
        }
        let html = try await fetchThreadHTML(threadID: thread.tid, view: view, authorID: authorID)
        let parsed = try ForumThreadPageHTMLParser.parsePage(from: html, thread: thread, fallbackTitle: title)
        try? await forumCacheStore.saveThreadPage(parsed, thread: thread, pageNumber: view, authorID: authorID)
        return parsed
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
