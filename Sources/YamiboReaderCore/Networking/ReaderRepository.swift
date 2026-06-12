import Foundation

public actor ReaderRepository {
    private let client: YamiboClient
    private let cacheStore: ReaderCacheStore

    public init(client: YamiboClient, cacheStore: ReaderCacheStore = ReaderCacheStore()) {
        self.client = client
        self.cacheStore = cacheStore
    }

    public func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        try await loadPage(request, ignoresCache: false)
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
        await cacheStore.cachedViews(for: threadURL, authorID: authorID, contentSource: contentSource)
    }

    public func deleteCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        try await cacheStore.deleteViews(views, for: threadURL, authorID: authorID, contentSource: contentSource)
    }

    public func refreshCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        let targets = views.isEmpty
            ? await cacheStore.cachedViews(for: threadURL, authorID: authorID, contentSource: contentSource)
            : views
        try await cacheStore.deleteViews(targets, for: threadURL, authorID: authorID, contentSource: contentSource)
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

    public func fetchThreadDisplayTitle(for threadURL: URL, authorID: String? = nil) async throws -> String {
        let html = try await client.fetchHTML(for: .thread(url: threadURL, page: 1, authorID: authorID))
        guard let title = ReaderHTMLParser.extractPageTitle(from: html) else {
            throw YamiboError.parsingFailed(context: L10n.string("context.thread_title"))
        }
        return title
    }

    public func loadChapterComments(for target: ReaderChapterCommentTarget) async throws -> ChapterCommentsPage {
        let html = try await client.fetchHTML(
            for: .thread(url: target.threadURL, page: target.view, authorID: target.authorID)
        )
        var page = try ChapterCommentsHTMLParser.parseInitialPage(html: html, target: target)
        if let fullRatingsURL = try ChapterCommentsHTMLParser.fullRatingReasonsURL(html: html, target: target),
           let fullRatingsHTML = try? await client.fetchHTML(url: fullRatingsURL) {
            let fullRatings = try ChapterCommentsHTMLParser.parseFullRatingReasonsPage(
                html: fullRatingsHTML,
                target: target
            )
            if !fullRatings.isEmpty {
                page.comments = Self.replacingPreviewRatings(in: page.comments, with: fullRatings)
            }
        }
        if target.authorID != nil,
           let unfilteredHTML = try? await loadUnfilteredChapterCommentHTML(for: target) {
            let unfilteredView = (try? ChapterCommentsHTMLParser.currentView(
                html: unfilteredHTML,
                fallback: target.view
            )) ?? target.view
            var unfilteredTarget = target
            unfilteredTarget.view = unfilteredView
            let unfilteredPage = try ChapterCommentsHTMLParser.parseInitialPage(
                html: unfilteredHTML,
                target: unfilteredTarget
            )
            page = Self.appendingSamePageReplies(from: unfilteredPage, to: page)
        }
        return page
    }

    public func loadMoreChapterComments(
        for target: ReaderChapterCommentTarget,
        view: Int
    ) async throws -> ChapterCommentsPage {
        let html = try await client.fetchHTML(
            for: .thread(url: Self.threadURLRemovingAuthorID(target.threadURL), page: view, authorID: nil),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try ChapterCommentsHTMLParser.parseContinuationPage(html: html, target: target, view: view)
    }

    private func loadUnfilteredChapterCommentHTML(for target: ReaderChapterCommentTarget) async throws -> String {
        if let findPostURL = Self.findPostURL(for: target),
           let html = try? await client.fetchHTML(
               url: findPostURL,
               cachePolicy: .reloadIgnoringLocalCacheData
           ) {
            return html
        }
        return try await client.fetchHTML(
            for: .thread(url: Self.threadURLRemovingAuthorID(target.threadURL), page: target.view, authorID: nil),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    private func loadPage(_ request: ReaderPageRequest, ignoresCache: Bool) async throws -> ReaderPageDocument {
        if !ignoresCache,
           let cached = await cacheStore.loadDocument(
               for: request,
               contentSource: request.authorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage
           ),
           !isLegacyCachedDocumentMissingChapterCommentSources(cached),
           !isCachedDocumentMissingAuthorReplyMetadata(cached) {
            return cached
        }

        do {
            let initialHTML = try await client.fetchHTML(
                for: .thread(url: request.threadURL, page: request.view, authorID: request.authorID)
            )
            let document = try await parsePreferredDocument(from: initialHTML, request: request)
            try await cacheStore.save(document)
            return document
        } catch let error as URLError {
            if let cached = await cacheStore.loadDocument(
                for: request,
                contentSource: request.authorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage
            ) {
                return cached
            }
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw YamiboError.offline
            }
            throw YamiboError.underlying(error.localizedDescription)
        } catch {
            if let cached = await cacheStore.loadDocument(
                for: request,
                contentSource: request.authorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage
            ) {
                return cached
            }
            throw error
        }
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

    private static func replacingPreviewRatings(
        in comments: [ChapterComment],
        with fullRatings: [ChapterComment]
    ) -> [ChapterComment] {
        let insertionIndex = comments.firstIndex { $0.source == .ratingReason }
            ?? comments.firstIndex { $0.source != .postComment }
            ?? comments.count
        let retainedBeforeInsertion = comments[..<insertionIndex].filter { $0.source != .ratingReason }.count
        var merged = comments.filter { $0.source != .ratingReason }
        merged.insert(contentsOf: fullRatings, at: retainedBeforeInsertion)
        return merged
    }

    private static func appendingSamePageReplies(
        from unfilteredPage: ChapterCommentsPage,
        to page: ChapterCommentsPage
    ) -> ChapterCommentsPage {
        let existingIDs = Set(page.comments.map(\.id))
        let replies = unfilteredPage.comments.filter { comment in
            comment.source == .reply && !existingIDs.contains(comment.id)
        }
        return ChapterCommentsPage(
            target: page.target,
            comments: page.comments + replies,
            isBoundaryClosed: unfilteredPage.isBoundaryClosed,
            nextView: unfilteredPage.nextView
        )
    }

    private static func threadURLRemovingAuthorID(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return url
        }
        components.queryItems = queryItems.filter { $0.name != "authorid" }
        return components.url ?? url
    }

    private static func findPostURL(for target: ReaderChapterCommentTarget) -> URL? {
        guard let threadID = ReaderHTMLParser.extractThreadID(from: target.threadURL),
              !target.ownerPostID.isEmpty else {
            return nil
        }
        var components = URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/forum.php"
        components?.queryItems = [
            .init(name: "mod", value: "redirect"),
            .init(name: "goto", value: "findpost"),
            .init(name: "ptid", value: threadID),
            .init(name: "pid", value: target.ownerPostID),
            .init(name: "mobile", value: "2")
        ]
        return components?.url
    }

    private func parsePreferredDocument(
        from initialHTML: String,
        request: ReaderPageRequest
    ) async throws -> ReaderPageDocument {
        if request.authorID == nil,
           let onlyAuthorID = ReaderHTMLParser.extractOnlyAuthorID(from: initialHTML, request: request) {
            let filteredRequest = ReaderPageRequest(
                threadURL: request.threadURL,
                view: request.view,
                authorID: onlyAuthorID
            )
            let filteredHTML = try await client.fetchHTML(
                for: .thread(url: filteredRequest.threadURL, page: filteredRequest.view, authorID: filteredRequest.authorID)
            )
            return try ReaderHTMLParser.parseDocument(
                html: filteredHTML,
                request: filteredRequest,
                contentSource: .authorFilteredPage
            )
        }

        let fallbackSource: ReaderContentSource = request.authorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage
        return try ReaderHTMLParser.parseDocument(
            html: initialHTML,
            request: request,
            contentSource: fallbackSource
        )
    }
}
