import Foundation
import Observation
import YamiboReaderCore

struct ForumNovelChapterSummary: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var view: Int
}

struct ForumNovelDetailHeaderSummary: Equatable, Sendable {
    var title: String
    var authorName: String?
    var postedAtText: String?
    var forumName: String?
    var totalViews: Int?
    var totalReplies: Int?
    var coverURL: URL?
    var chapterCount: Int
}

@MainActor
@Observable
final class ForumNovelDetailViewModel {
    var document: ReaderPageDocument?
    var threadPage: ForumThreadPage?
    var chapters: [ForumNovelChapterSummary] = []
    var favorite: Favorite?
    var isLoading = false
    var errorMessage: String?

    let context: NovelDetailLaunchContext

    @ObservationIgnored private let appContext: YamiboAppContext

    init(context: NovelDetailLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
    }

    var navigationTitle: String {
        context.title
    }

    var headerSummary: ForumNovelDetailHeaderSummary {
        let firstPost = threadPage?.posts.first
        return ForumNovelDetailHeaderSummary(
            title: Self.trimmedNonEmpty(threadPage?.title) ?? context.title,
            authorName: Self.trimmedNonEmpty(firstPost?.author.name),
            postedAtText: firstPost?.postedAtText,
            forumName: forumName,
            totalViews: threadPage?.totalViews,
            totalReplies: threadPage?.totalReplies,
            coverURL: firstCoverCandidate(in: firstPost),
            chapterCount: chapters.count
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
            let repository = await appContext.makeNovelReaderRepository()
            let threadRepository = await appContext.makeForumThreadReaderRepository()
            let loaded = try await repository.loadPage(
                ReaderPageRequest(
                    threadURL: context.thread.canonicalURL,
                    view: 1,
                    authorID: context.authorID
                )
            )
            let loadedThreadPage = try await threadRepository.fetchThreadPage(
                context: ThreadReaderLaunchContext(
                    thread: context.thread,
                    title: context.title,
                    authorID: context.authorID
                )
            )
            document = loaded
            threadPage = loadedThreadPage
            chapters = Self.chapterSummaries(from: loaded)
        } catch {
            document = nil
            threadPage = nil
            chapters = []
            errorMessage = error.localizedDescription
        }
    }

    func launchContext(for chapter: ForumNovelChapterSummary?) -> ReaderLaunchContext {
        ReaderLaunchContext(
            threadURL: context.thread.canonicalURL,
            threadTitle: context.title,
            source: .forum,
            initialView: chapter?.view ?? 1,
            authorID: context.authorID
        )
    }

    func continueLaunchContext() -> ReaderLaunchContext {
        let resumePoint = favorite?.novelResumePoint
        return ReaderLaunchContext(
            threadURL: context.thread.canonicalURL,
            threadTitle: favorite?.resolvedDisplayTitle ?? context.title,
            source: resumePoint == nil && (favorite?.lastView ?? 1) <= 1 ? .forum : .resume,
            initialView: resumePoint?.view ?? favorite?.lastView ?? 1,
            authorID: resumePoint?.authorID ?? favorite?.authorID ?? context.authorID,
            initialResumePoint: resumePoint
        )
    }

    private static func chapterSummaries(from document: ReaderPageDocument) -> [ForumNovelChapterSummary] {
        var seen: Set<String> = []
        var summaries: [ForumNovelChapterSummary] = []

        for segment in document.segments {
            guard let title = segment.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  seen.insert(title).inserted else {
                continue
            }
            summaries.append(
                ForumNovelChapterSummary(
                    id: "\(document.view)|\(title)",
                    title: title,
                    view: document.view
                )
            )
        }

        return summaries
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

    private func firstCoverCandidate(in post: ForumThreadPost?) -> URL? {
        post?.contentBlocks.lazy.compactMap(Self.coverCandidateURL(in:)).first
    }

    private static func coverCandidateURL(in block: ForumThreadContentBlock) -> URL? {
        switch block.kind {
        case let .image(image):
            return isCoverCandidate(image) ? image.url : nil
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
        guard !image.isEmoticon else { return false }
        let value = image.url.absoluteString.lowercased()
        return !value.contains("none.gif")
            && !value.contains("smiley/")
            && !value.contains("face")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
