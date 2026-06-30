import Foundation
import Observation
import YamiboReaderCore

protocol ForumNovelDocumentLoading: Sendable {
    func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument
}

extension NovelReaderRepository: ForumNovelDocumentLoading {}

protocol ForumNovelThreadPageLoading: Sendable {
    func fetchNovelThreadPage(context: NovelDetailLaunchContext, page: Int) async throws -> ForumThreadPage
}

extension ForumThreadReaderRepository: ForumNovelThreadPageLoading {}

struct ForumNovelChapterSummary: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var view: Int
    var postID: String? = nil
    var floorText: String? = nil
    var resumePoint: ReaderResumePoint? = nil
    var progressText: String? = nil
    var isCurrentRead: Bool = false
}

struct ForumNovelChapterSection: Identifiable, Hashable, Sendable {
    var page: Int
    var chapters: [ForumNovelChapterSummary]
    var isLoaded: Bool
    var isLoading: Bool
    var errorMessage: String?

    var id: Int { page }
}

struct ForumNovelDetailHeaderSummary: Equatable, Sendable {
    var title: String
    var threadURL: URL
    var authorID: String?
    var authorName: String?
    var postedAtText: String?
    var lastUpdatedText: String?
    var forumName: String?
    var totalViews: Int?
    var totalReplies: Int?
    var coverURL: URL?
    var chapterCount: Int
    var firstFloorPreviewText: String?
    var readingProgressText: String?
    var isFavorited: Bool
}

@MainActor
@Observable
final class ForumNovelDetailViewModel {
    var document: ReaderPageDocument?
    var threadPage: ForumThreadPage?
    var chapters: [ForumNovelChapterSummary] = []
    var chapterSections: [ForumNovelChapterSection] = []
    var expandedChapterPages: Set<Int> = [1]
    var favorite: Favorite?
    var readingProgress: ReadingProgressRecord?
    var contentCover: ContentCover?
    var isLoading = false
    var errorMessage: String?
    var favoriteErrorMessage: String?

    let context: NovelDetailLaunchContext

    @ObservationIgnored private let appContext: YamiboAppContext
    @ObservationIgnored private var loadedThreadPages: [Int: ForumThreadPage] = [:]
    @ObservationIgnored private var loadingChapterPages: Set<Int> = []
    @ObservationIgnored private var chapterPageErrors: [Int: String] = [:]
    @ObservationIgnored private var totalChapterPages = 1
    @ObservationIgnored private var favoriteUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var readingProgressUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private let novelRepositoryProvider: @Sendable () async -> any ForumNovelDocumentLoading
    @ObservationIgnored private let threadRepositoryProvider: @Sendable () async -> any ForumNovelThreadPageLoading

    init(
        context: NovelDetailLaunchContext,
        appContext: YamiboAppContext,
        novelRepositoryProvider: (@Sendable () async -> any ForumNovelDocumentLoading)? = nil,
        threadRepositoryProvider: (@Sendable () async -> any ForumNovelThreadPageLoading)? = nil
    ) {
        self.context = context
        self.appContext = appContext
        self.novelRepositoryProvider = novelRepositoryProvider ?? {
            await appContext.makeNovelReaderRepository()
        }
        self.threadRepositoryProvider = threadRepositoryProvider ?? {
            await appContext.makeForumThreadReaderRepository()
        }
        favoriteUpdatesTask = Task { @MainActor [weak self, favoriteStore = appContext.favoriteStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteStore.changeIDUserInfoKey] as? String,
                      changeID == favoriteStore.changeID else {
                    continue
                }
                await self.refreshFavorite(from: favoriteStore)
            }
        }
        readingProgressUpdatesTask = Task { @MainActor [weak self, readingProgressStore = appContext.readingProgressStore] in
            for await notification in NotificationCenter.default.notifications(named: ReadingProgressStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[ReadingProgressStore.changeIDUserInfoKey] as? String,
                      changeID == readingProgressStore.changeID else {
                    continue
                }
                await self.refreshReadingProgress(from: readingProgressStore)
            }
        }
    }

    deinit {
        favoriteUpdatesTask?.cancel()
        readingProgressUpdatesTask?.cancel()
    }

    var navigationTitle: String {
        displayTitle(threadPage?.title ?? context.title)
    }

    var hasReadingProgress: Bool {
        Self.hasReadingProgress(readingProgress, favorite: favorite)
    }

    var headerSummary: ForumNovelDetailHeaderSummary {
        let firstPost = threadPage?.posts.first
        return ForumNovelDetailHeaderSummary(
            title: displayTitle(threadPage?.title ?? context.title),
            threadURL: context.thread.canonicalURL,
            authorID: Self.trimmedNonEmpty(firstPost?.author.uid) ?? context.authorID,
            authorName: Self.trimmedNonEmpty(firstPost?.author.name),
            postedAtText: firstPost?.postedAtText,
            lastUpdatedText: Self.lastUpdatedText(
                editedText: firstPost?.lastEditedText,
                postedAtText: firstPost?.postedAtText
            ),
            forumName: forumName,
            totalViews: threadPage?.totalViews,
            totalReplies: threadPage?.totalReplies,
            coverURL: contentCover?.resolvedURL ?? Self.coverCandidate(in: threadPage),
            chapterCount: chapters.count,
            firstFloorPreviewText: Self.firstFloorPreviewText(from: firstPost),
            readingProgressText: Self.readingProgressText(from: readingProgress, favorite: favorite),
            isFavorited: favorite != nil
        )
    }

    func load() async {
        guard document == nil else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            favorite = await appContext.favoriteStore.favorite(for: context.thread.canonicalURL)
            readingProgress = await appContext.readingProgressStore.load(for: context.thread.canonicalURL)
            contentCover = await loadContentCover()
            favoriteErrorMessage = nil
            let repository = await novelRepositoryProvider()
            let threadRepository = await threadRepositoryProvider()
            async let loadedDocument = repository.loadPage(
                ReaderPageRequest(
                    threadURL: context.thread.canonicalURL,
                    view: 1,
                    authorID: context.authorID
                )
            )
            async let loadedInitialThreadPage = threadRepository.fetchNovelThreadPage(context: context, page: 1)
            let loadedThreadPage = try await loadedInitialThreadPage
            threadPage = loadedThreadPage
            loadedThreadPages = [1: loadedThreadPage]
            await refreshContentCover(from: loadedThreadPage, using: threadRepository)
            let loaded = try await loadedDocument
            document = loaded
            totalChapterPages = Self.totalPages(from: loadedThreadPage, fallback: 1)
            chapterPageErrors = [:]
            loadingChapterPages = []
            expandedChapterPages = [1]
            rebuildChapterDirectory()
        } catch {
            document = nil
            threadPage = nil
            chapters = []
            chapterSections = []
            readingProgress = await appContext.readingProgressStore.load(for: context.thread.canonicalURL)
            contentCover = await loadContentCover()
            loadedThreadPages = [:]
            chapterPageErrors = [:]
            loadingChapterPages = []
            errorMessage = error.localizedDescription
        }
    }

    func launchContext(for chapter: ForumNovelChapterSummary?) -> ReaderLaunchContext {
        ReaderLaunchContext(
            threadURL: context.thread.canonicalURL,
            threadTitle: context.title,
            source: .forum,
            initialView: chapter?.view ?? 1,
            authorID: chapter?.resumePoint?.authorID ?? context.authorID,
            initialResumePoint: chapter?.resumePoint
        )
    }

    func continueLaunchContext() -> ReaderLaunchContext {
        let novelProgress = readingProgress?.novel
        let resumePoint = novelProgress?.novelResumePoint ?? favorite?.novelResumePoint
        let hasProgress = Self.hasReadingProgress(readingProgress, favorite: favorite)
        return ReaderLaunchContext(
            threadURL: context.thread.canonicalURL,
            threadTitle: favorite?.resolvedDisplayTitle ?? context.title,
            source: hasProgress ? .resume : .forum,
            initialView: resumePoint?.view ?? novelProgress?.lastView ?? favorite?.lastView ?? 1,
            authorID: resumePoint?.authorID ?? novelProgress?.authorID ?? favorite?.authorID ?? context.authorID,
            initialResumePoint: resumePoint
        )
    }

    func toggleChapterSection(page: Int) async {
        let normalizedPage = max(1, page)
        if expandedChapterPages.contains(normalizedPage) {
            expandedChapterPages.remove(normalizedPage)
            rebuildChapterDirectory()
            return
        }

        expandedChapterPages.insert(normalizedPage)
        rebuildChapterDirectory()
        guard loadedThreadPages[normalizedPage] == nil else { return }
        await loadChapterSection(page: normalizedPage)
    }

    func loadChapterSection(page: Int) async {
        let normalizedPage = max(1, page)
        guard loadedThreadPages[normalizedPage] == nil,
              !loadingChapterPages.contains(normalizedPage) else {
            return
        }

        loadingChapterPages.insert(normalizedPage)
        chapterPageErrors[normalizedPage] = nil
        rebuildChapterDirectory()
        defer {
            loadingChapterPages.remove(normalizedPage)
            rebuildChapterDirectory()
        }

        do {
            let repository = await threadRepositoryProvider()
            let loaded = try await repository.fetchNovelThreadPage(context: context, page: normalizedPage)
            loadedThreadPages[normalizedPage] = loaded
            totalChapterPages = max(totalChapterPages, Self.totalPages(from: loaded, fallback: normalizedPage))
            chapterPageErrors[normalizedPage] = nil
        } catch {
            chapterPageErrors[normalizedPage] = error.localizedDescription
        }
    }

    func toggleFavorite() async {
        let favoriteStore = appContext.favoriteStore
        let url = context.thread.canonicalURL
        favoriteErrorMessage = nil

        do {
            if let favorite {
                try await ForumThreadFavoriteSync.removeFavorite(
                    favorite,
                    favoriteStore: favoriteStore,
                    readingProgressStore: appContext.readingProgressStore,
                    remoteRepository: await appContext.makeFavoriteRepository()
                )
                self.favorite = nil
                rebuildChapterDirectory()
                return
            }

            let favorite = try await ForumThreadFavoriteSync.addFavorite(
                threadURL: url,
                title: favoriteTitle,
                type: .novel,
                authorID: context.authorID,
                formHash: threadPage?.formHash,
                favoriteStore: favoriteStore,
                remoteRepository: await appContext.makeFavoriteRepository()
            )
            self.favorite = favorite
            rebuildChapterDirectory()
        } catch {
            favoriteErrorMessage = error.localizedDescription
            favorite = await favoriteStore.favorite(for: url)
            rebuildChapterDirectory()
        }
    }

    func clearFavoriteError() {
        favoriteErrorMessage = nil
    }

    private func refreshFavorite(from favoriteStore: FavoriteStore) async {
        favorite = await favoriteStore.favorite(for: context.thread.canonicalURL)
        rebuildChapterDirectory()
    }

    private func refreshReadingProgress(from readingProgressStore: ReadingProgressStore) async {
        readingProgress = await readingProgressStore.load(for: context.thread.canonicalURL)
        rebuildChapterDirectory()
    }

    static func chapterSections(
        from loadedPages: [Int: ForumThreadPage],
        totalPages: Int,
        loadingPages: Set<Int> = [],
        pageErrors: [Int: String] = [:],
        readingProgress: ReadingProgressRecord? = nil,
        favorite: Favorite? = nil
    ) -> [ForumNovelChapterSection] {
        let normalizedTotal = max(1, totalPages)
        return (1...normalizedTotal).map { page in
            let pageDocument = loadedPages[page]
            let chapters = pageDocument.map { chapterSummaries(from: $0, page: page) } ?? []
            return ForumNovelChapterSection(
                page: page,
                chapters: chapters.map { chapter in
                    var updatedChapter = chapter
                    updatedChapter.progressText = chapterProgressText(
                        for: chapter,
                        readingProgress: readingProgress,
                        favorite: favorite
                    )
                    updatedChapter.isCurrentRead = isCurrentReadChapter(
                        chapter,
                        readingProgress: readingProgress,
                        favorite: favorite
                    )
                    return updatedChapter
                },
                isLoaded: pageDocument != nil,
                isLoading: loadingPages.contains(page),
                errorMessage: pageErrors[page]
            )
        }
    }

    private func rebuildChapterDirectory() {
        chapterSections = Self.chapterSections(
            from: loadedThreadPages,
            totalPages: totalChapterPages,
            loadingPages: loadingChapterPages,
            pageErrors: chapterPageErrors,
            readingProgress: readingProgress,
            favorite: favorite
        )
        chapters = chapterSections.flatMap(\.chapters)
    }

    func refreshContentCover(from page: ForumThreadPage) async {
        await refreshContentCover(from: page, using: nil)
    }

    private func refreshContentCover(
        from page: ForumThreadPage,
        using repository: (any ForumNovelThreadPageLoading)?
    ) async {
        guard let key = contentCoverKey else { return }
        if let candidate = await resolveCoverCandidate(from: page, using: repository) {
            do {
                _ = try await appContext.contentCoverStore.setAutomaticCover(candidate, for: key)
            } catch {
                return
            }
        }
        contentCover = await appContext.contentCoverStore.cover(for: key)
    }

    private func resolveCoverCandidate(
        from page: ForumThreadPage,
        using repository: (any ForumNovelThreadPageLoading)?
    ) async -> URL? {
        if let candidate = Self.coverCandidate(in: page) {
            return candidate
        }
        guard let owner = Self.coverOwner(in: page) else {
            return nil
        }
        let currentPage = page.pageNavigation?.currentPage
        for pageNumber in loadedThreadPages.keys.sorted() {
            guard pageNumber != currentPage else { continue }
            if let candidate = loadedThreadPages[pageNumber].flatMap({ Self.coverCandidate(in: $0, owner: owner) }) {
                return candidate
            }
        }
        guard let repository else {
            return nil
        }

        let totalPages = Self.totalPages(from: page, fallback: 1)
        guard totalPages > 1 else {
            return nil
        }
        let ownerContext = NovelDetailLaunchContext(
            thread: context.thread,
            title: context.title,
            authorID: Self.trimmedNonEmpty(owner.uid) ?? context.authorID
        )
        for pageNumber in 1...totalPages where loadedThreadPages[pageNumber] == nil {
            guard let loaded = try? await repository.fetchNovelThreadPage(context: ownerContext, page: pageNumber) else {
                continue
            }
            if let candidate = Self.coverCandidate(in: loaded, owner: owner) {
                return candidate
            }
        }
        return nil
    }

    private static func chapterSummaries(from page: ForumThreadPage, page pageNumber: Int) -> [ForumNovelChapterSummary] {
        page.posts.enumerated().map { offset, post in
            let title = chapterTitle(from: post)
            return ForumNovelChapterSummary(
                id: "\(pageNumber)|\(post.postID)",
                title: title,
                view: pageNumber,
                postID: post.postID,
                floorText: post.floorText,
                resumePoint: resumePoint(
                    forPostID: post.postID,
                    title: title,
                    view: pageNumber,
                    ordinal: offset
                )
            )
        }
    }

    private static func resumePoint(
        forPostID postID: String,
        title: String,
        view: Int,
        ordinal: Int
    ) -> ReaderResumePoint? {
        let normalizedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPostID.isEmpty else { return nil }
        let chapterIdentity = NovelChapterIdentity(rawValue: "post:\(normalizedPostID)#chapter:0")
        return ReaderResumePoint(
            view: view,
            chapterIdentity: chapterIdentity,
            textSegmentIdentity: nil,
            displayedTextOffset: 0,
            chapterOrdinal: ordinal,
            chapterTitle: title,
            segmentProgress: 0,
            readingModeHint: .vertical
        )
    }

    private static func chapterTitle(from post: ForumThreadPost) -> String {
        let sourceText = chapterTitleCandidate(in: post.contentBlocks) ?? post.contentText
        let firstLine = sourceText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { isChapterTitleCandidate($0) })
            .map { String($0.prefix(30)) }
        return ReaderChapterTitleNormalizer.normalize(firstLine)
            ?? post.floorText
            ?? L10n.string("reader.title")
    }

    private static func chapterTitleCandidate(in blocks: [ForumThreadContentBlock]) -> String? {
        blocks.lazy.compactMap { block -> String? in
            switch block.kind {
            case let .text(text):
                return text.text
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: isChapterTitleCandidate)
            case .image, .attachment, .quote, .code, .horizontalRule, .collapse, .locked, .table:
                return nil
            }
        }.first
    }

    private static func isChapterTitleCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        return !lowered.hasPrefix("本帖最后由")
            && !lowered.hasPrefix("posted by")
            && !lowered.hasPrefix("引用")
            && !lowered.hasPrefix("quote")
            && !lowered.hasPrefix("查看完整版本")
    }

    private static func totalPages(from page: ForumThreadPage, fallback: Int) -> Int {
        max(fallback, page.pageNavigation?.totalPages ?? page.pageNavigation?.currentPage ?? fallback)
    }

    private var forumName: String? {
        if let forumName = Self.trimmedNonEmpty(threadPage?.forumName) {
            return "#\(forumName)"
        }
        guard let fid = Self.trimmedNonEmpty(threadPage?.thread.fid)
            ?? Self.trimmedNonEmpty(context.thread.fid) else {
            return nil
        }
        return "#\(fid)"
    }

    private var favoriteTitle: String {
        displayTitle(threadPage?.title ?? context.title)
    }

    private func displayTitle(_ value: String?) -> String {
        ForumThreadTitleSanitizer.sanitize(value)
            ?? context.thread.canonicalURL.absoluteString
    }

    private static func firstFloorPreviewText(from post: ForumThreadPost?) -> String? {
        guard let post else { return nil }
        let text = post.contentText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return trimmedNonEmpty(text)
    }

    private static func readingProgressText(from readingProgress: ReadingProgressRecord?, favorite: Favorite?) -> String? {
        if let novel = readingProgress?.novel,
           hasReadingProgress(readingProgress, favorite: nil) {
            return readingProgressText(from: novel)
        }
        guard let favorite,
              hasReadingProgress(nil, favorite: favorite) else {
            return nil
        }
        if let percent = favorite.novelDocumentSurfaceProgressPercent {
            if let maxView = favorite.novelMaxView, maxView > 1 {
                return L10n.string(
                    "favorites.progress.novel_page_web",
                    percent,
                    min(max(favorite.lastView, 1), maxView),
                    maxView
                )
            }
            return L10n.string("favorites.progress.novel_percent", percent)
        }
        if let maxView = favorite.novelMaxView, maxView > 1 {
            return L10n.string(
                "favorites.progress.novel_web",
                min(max(favorite.lastView, 1), maxView),
                maxView
            )
        }
        return trimmedNonEmpty(favorite.novelResumePoint?.chapterTitle)
            ?? trimmedNonEmpty(favorite.lastChapter)
            ?? L10n.string("favorites.progress.page", favorite.lastView)
    }

    private static func readingProgressText(from novel: NovelReadingProgressRecord) -> String {
        if let percent = novel.novelDocumentSurfaceProgressPercent {
            if let maxView = novel.novelMaxView, maxView > 1 {
                return L10n.string(
                    "favorites.progress.novel_page_web",
                    percent,
                    min(max(novel.lastView, 1), maxView),
                    maxView
                )
            }
            return L10n.string("favorites.progress.novel_percent", percent)
        }
        if let maxView = novel.novelMaxView, maxView > 1 {
            return L10n.string(
                "favorites.progress.novel_web",
                min(max(novel.lastView, 1), maxView),
                maxView
            )
        }
        return trimmedNonEmpty(novel.novelResumePoint?.chapterTitle)
            ?? trimmedNonEmpty(novel.lastChapter)
            ?? L10n.string("favorites.progress.page", novel.lastView)
    }

    private static func chapterProgressText(
        for chapter: ForumNovelChapterSummary,
        readingProgress: ReadingProgressRecord?,
        favorite: Favorite?
    ) -> String? {
        guard isCurrentReadChapter(chapter, readingProgress: readingProgress, favorite: favorite) else {
            return nil
        }
        if let percent = readingProgress?.novel?.novelDocumentSurfaceProgressPercent
            ?? favorite?.novelDocumentSurfaceProgressPercent {
            return L10n.string("favorites.progress.novel_percent", percent)
        }
        return L10n.string("forum.thread_route.current_chapter_hint")
    }

    private static func isCurrentReadChapter(
        _ chapter: ForumNovelChapterSummary,
        readingProgress: ReadingProgressRecord?,
        favorite: Favorite?
    ) -> Bool {
        let novel = readingProgress?.novel
        let resumePoint = novel?.novelResumePoint ?? favorite?.novelResumePoint
        if let resumeIdentity = resumePoint?.chapterIdentity,
           resumeIdentity == chapter.resumePoint?.chapterIdentity {
            return true
        }
        if let postID = chapter.postID,
           resumePoint?.chapterIdentity?.rawValue.hasPrefix("post:\(postID)#") == true {
            return true
        }
        let lastView = novel?.lastView ?? favorite?.lastView
        let lastChapter = novel?.lastChapter ?? favorite?.lastChapter
        return lastView == chapter.view
            && trimmedNonEmpty(lastChapter) == trimmedNonEmpty(chapter.title)
    }

    private static func hasReadingProgress(_ readingProgress: ReadingProgressRecord?, favorite: Favorite?) -> Bool {
        if let novel = readingProgress?.novel {
            return novel.novelResumePoint != nil
                || novel.lastView > 1
                || trimmedNonEmpty(novel.lastChapter) != nil
                || trimmedNonEmpty(novel.authorID) != nil
                || novel.novelMaxView != nil
                || novel.novelDocumentSurfaceProgressPercent != nil
        }
        guard let favorite else { return false }
        return favorite.novelResumePoint != nil
            || favorite.lastView > 1
            || trimmedNonEmpty(favorite.lastChapter) != nil
            || trimmedNonEmpty(favorite.authorID) != nil
            || favorite.novelMaxView != nil
            || favorite.novelDocumentSurfaceProgressPercent != nil
    }

    private var contentCoverKey: ContentCoverKey? {
        let tid = context.thread.tid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else { return nil }
        return ContentCoverKey(targetType: .threadNovel, targetID: tid)
    }

    private func loadContentCover() async -> ContentCover? {
        guard let key = contentCoverKey else { return nil }
        return await appContext.contentCoverStore.cover(for: key)
    }

    static func coverCandidate(in page: ForumThreadPage?) -> URL? {
        guard let page,
              let owner = coverOwner(in: page) else {
            return nil
        }
        return coverCandidate(in: page, owner: owner)
    }

    private static func coverOwner(in page: ForumThreadPage) -> BlogReaderUser? {
        firstFloorPost(in: page.posts)?.author ?? page.posts.first?.author
    }

    private static func coverCandidate(in page: ForumThreadPage, owner: BlogReaderUser) -> URL? {
        let ownerUID = trimmedNonEmpty(owner.uid)
        let ownerName = trimmedNonEmpty(owner.name)
        return page.posts
            .filter { post in
                if let ownerUID {
                    return trimmedNonEmpty(post.author.uid) == ownerUID
                }
                guard let ownerName else { return false }
                return trimmedNonEmpty(post.author.name) == ownerName
            }
            .flatMap(\.contentBlocks)
            .lazy
            .compactMap(Self.coverCandidateURL(in:))
            .first
    }

    private static func firstFloorPost(in posts: [ForumThreadPost]) -> ForumThreadPost? {
        posts.first { post in
            let floorText = post.floorText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return floorText == "1" || floorText.hasPrefix("1#")
        }
    }

    private static func coverCandidateURL(in block: ForumThreadContentBlock) -> URL? {
        switch block.kind {
        case let .image(image):
            return isCoverCandidate(image) ? ContentCoverStore.normalizedCoverURL(from: image.url.absoluteString) : nil
        case let .quote(blocks), let .collapse(_, blocks), let .locked(_, blocks):
            return blocks.lazy.compactMap(coverCandidateURL(in:)).first
        case let .table(rows):
            return rows.lazy
                .flatMap { $0 }
                .flatMap(\.blocks)
                .compactMap(coverCandidateURL(in:))
                .first
        case .text, .attachment, .code, .horizontalRule:
            return nil
        }
    }

    private static func isCoverCandidate(_ image: ForumThreadImageBlock) -> Bool {
        !image.isEmoticon && ContentCoverStore.normalizedCoverURL(from: image.url.absoluteString) != nil
    }

    private static func lastUpdatedText(editedText: String?, postedAtText: String?) -> String? {
        guard let editedText = trimmedNonEmpty(editedText) else {
            return trimmedNonEmpty(postedAtText)
        }
        return extractedEditTime(from: editedText) ?? editedText
    }

    private static func extractedEditTime(from text: String) -> String? {
        let patterns = [
            #"(?:本帖最后由|本帖最後由)\s+.+?\s+(?:于|於)\s+(.+?)\s+(?:编辑|編輯)"#,
            #"(?:最后编辑于|最後編輯於)\s*(.+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let searchRange = NSRange(text.startIndex ..< text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: searchRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let value = trimmedNonEmpty(String(text[range])) else {
                continue
            }
            return value
        }
        return nil
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
