import Foundation
import YamiboReaderCore

enum LocalFavoriteOpenTarget: Sendable {
    case novelReader(NovelLaunchContext)
    case mangaReader(MangaLaunchContext)
    case nativeThread(url: URL, title: String)
}

/// Semantic open failures; the presentation layer supplies the localized
/// description (see `FavoritePresentation.swift`).
enum LocalFavoriteOpenError: Error {
    case mangaTitleUnresolved
}

/// Resolves a favorite item into a concrete reader launch target, combining
/// the latest stored item with its reading progress.
struct LocalFavoriteOpenTargetResolver {
    let libraryStore: FavoriteLibraryStore
    let readingProgressStore: ReadingProgressStore

    func openTarget(for item: FavoriteItem, mode: FavoriteLaunchMode = .resume) async throws -> LocalFavoriteOpenTarget? {
        let latestDocument = try await libraryStore.load()
        guard let latestItem = latestDocument.items.first(where: { $0.id == item.id }) else {
            return nil
        }

        let progress = await progressRecord(for: latestItem)
        switch latestItem.target {
        case let .novelThread(threadID):
            let novel = progress?.novel
            let resumePoint = mode == .start ? nil : novel?.novelResumePoint
            return .novelReader(
                NovelLaunchContext(
                    threadID: threadID,
                    threadTitle: latestItem.resolvedDisplayTitle,
                    source: .favorites,
                    initialView: mode == .start ? 1 : (resumePoint?.view ?? novel?.lastView),
                    authorID: resumePoint?.authorID ?? novel?.authorID,
                    initialResumePoint: resumePoint
                )
            )
        case .normalThread:
            guard let threadID = latestItem.target.threadID else { return nil }
            let url = YamiboRoute.threadByID(tid: threadID, page: 1, authorID: nil, reverse: false).url
            return .nativeThread(url: url, title: latestItem.resolvedDisplayTitle)
        case let .mangaTitle(_, cleanBookName):
            let progressManga = mode == .start ? nil : progress?.manga
            let metadata = latestItem.mangaChapterMetadata
            guard let chapterTID = progressManga?.chapterThreadID ?? metadata?.chapterTID else {
                throw LocalFavoriteOpenError.mangaTitleUnresolved
            }
            let originalThreadID = metadata?.chapterTID ?? chapterTID
            return .mangaReader(
                MangaLaunchContext(
                    originalThreadID: originalThreadID,
                    chapterTID: chapterTID,
                    displayTitle: latestItem.resolvedDisplayTitle,
                    source: .favorites,
                    chapterView: progressManga?.chapterView ?? metadata?.chapterView ?? 1,
                    initialPage: mode == .start ? 0 : (progress?.manga?.mangaPageIndex ?? 0),
                    directoryName: cleanBookName,
                    offlineCacheFavoriteID: latestItem.id
                )
            )
        }
    }

    private func progressRecord(for item: FavoriteItem) async -> ReadingProgressRecord? {
        switch item.target {
        case let .normalThread(threadID), let .novelThread(threadID):
            return await readingProgressStore.load(threadID: threadID)
        case .mangaTitle:
            if let progress = await readingProgressStore.load(for: item.target) {
                return progress
            }
            if let threadID = item.mangaChapterMetadata?.chapterTID {
                return await readingProgressStore.load(threadID: threadID)
            }
            return nil
        }
    }
}
