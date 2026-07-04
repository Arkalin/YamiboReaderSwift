import Foundation

public actor YamiboMangaReaderProjectionLoader: MangaReaderProjectionSnapshotLoading {
    private let client: YamiboClient
    private let projectionStore: any MangaReaderProjectionPersisting
    private let forumCacheStore: ForumCacheStore
    private var inFlightTasks: [String: Task<MangaReaderProjectionSnapshot, Error>] = [:]

    public init(
        client: YamiboClient,
        projectionStore: any MangaReaderProjectionPersisting,
        forumCacheStore: ForumCacheStore
    ) {
        self.client = client
        self.projectionStore = projectionStore
        self.forumCacheStore = forumCacheStore
    }

    public func loadReaderProjection(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjection {
        try await loadReaderProjectionSnapshot(request, ignoresCache: false).projection
    }

    public func loadReaderProjectionSnapshot(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjectionSnapshot {
        try await loadReaderProjectionSnapshot(request, ignoresCache: false)
    }

    public func loadReaderProjectionIgnoringCache(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjection {
        try await loadReaderProjectionSnapshot(request, ignoresCache: true).projection
    }

    private func loadReaderProjectionSnapshot(
        _ request: MangaReaderProjectionRequest,
        ignoresCache: Bool
    ) async throws -> MangaReaderProjectionSnapshot {
        let thread = ThreadIdentity(tid: request.threadID)
        let view = request.view
        let authorID = try await resolveAuthorID(
            requestedAuthorID: request.authorID,
            thread: thread,
            ignoresCache: ignoresCache
        )
        let identity = MangaReaderProjectionSourceIdentity(
            tid: request.threadID,
            authorID: authorID,
            contentSource: .authorFilteredPage,
            view: view
        )
        let taskKey = [identity.tid, identity.authorID ?? "all", String(identity.view), ignoresCache ? "refresh" : "cache"]
            .joined(separator: "\u{1F}")
        if let task = inFlightTasks[taskKey] {
            return try await task.value
        }

        let task = Task<MangaReaderProjectionSnapshot, Error> {
            let sourcePage = try await self.loadAuthorScopedThreadPage(
                thread: thread,
                authorID: authorID,
                view: view,
                ignoresCache: ignoresCache
            )
            let fingerprint = Self.projectionFingerprint(page: sourcePage, identity: identity)

            if !ignoresCache,
               let cached = await projectionStore.projection(for: identity),
               Self.isReusableProjection(cached, identity: identity, fingerprint: fingerprint) {
                return MangaReaderProjectionSnapshot(projection: cached, sourcePage: sourcePage)
            }

            let projection = try Self.deriveProjection(
                from: sourcePage,
                identity: identity,
                sourceFingerprint: fingerprint
            )
            try? await projectionStore.save(projection)
            return MangaReaderProjectionSnapshot(projection: projection, sourcePage: sourcePage)
        }
        inFlightTasks[taskKey] = task
        defer { inFlightTasks.removeValue(forKey: taskKey) }
        return try await task.value
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

    private static func deriveProjection(
        from page: ForumThreadPage,
        identity: MangaReaderProjectionSourceIdentity,
        sourceFingerprint: String
    ) throws -> MangaReaderProjection {
        guard identity.contentSource == .authorFilteredPage,
              identity.authorID?.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.parsingFailed(context: "漫画作者范围")
        }
        let imageURLs = orderedImageURLs(from: page)
        guard !imageURLs.isEmpty else {
            throw MangaReaderDataSupport.currentMangaChapterParsingFailure()
        }
        let ownerPost = page.posts.first
        let rawTitle = page.title.mangaReaderTrimmedNonEmpty ?? identity.tid
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
            sourceFingerprint: sourceFingerprint,
            schemaVersion: MangaReaderProjection.schemaVersion,
            parserVersion: MangaReaderProjection.parserVersion
        )
    }

    private static func isReusableProjection(
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

    private static func orderedImageURLs(from page: ForumThreadPage) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for post in page.posts {
            for image in post.images {
                guard let url = HTMLTextExtractor.absoluteURL(from: image.url, baseURL: page.thread.canonicalURL) else {
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
