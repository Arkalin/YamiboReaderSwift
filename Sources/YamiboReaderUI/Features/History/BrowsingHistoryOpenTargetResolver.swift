import Foundation
import YamiboReaderCore

enum BrowsingHistoryOpenTarget: Sendable {
    case novelReader(NovelLaunchContext)
    case mangaReader(MangaLaunchContext)
    case nativeThread(url: URL, title: String)
}

/// Resolves a browsing-history row into a concrete open target, mirroring
/// `LocalFavoriteOpenTargetResolver`'s resume semantics per content form:
///
/// - Normal threads open at page 1 with no explicit target — the thread
///   reader itself restores the saved page + floor anchor on every entrance
///   (browsing-history decision #8), so history adds nothing here.
/// - Novels resume via their `.novelThread` progress record.
/// - Manga routes by the board's *current* Smart Comic Mode (PRD
///   compatibility note), re-checked through the same
///   `isSmartComicModeEnabled(forumID:)` helper favorites use — including
///   its documented permissive default when the row carries no fid.
struct BrowsingHistoryOpenTargetResolver {
    let readingProgressStore: ReadingProgressStore
    let mangaDirectoryStore: any MangaDirectoryPersisting
    let settingsStore: SettingsStore

    func openTarget(for entry: BrowsingHistoryEntry) async -> BrowsingHistoryOpenTarget? {
        switch entry.target {
        case let .normalThread(threadID):
            let url = YamiboRoute.threadByID(tid: threadID, page: 1, authorID: nil, reverse: false).url
            return .nativeThread(url: url, title: entry.title)

        case let .novelThread(threadID):
            let novel = await readingProgressStore.load(for: .novelThread(threadID: threadID))?.novel
            let resumePoint = novel?.novelResumePoint
            return .novelReader(
                NovelLaunchContext(
                    threadID: threadID,
                    threadTitle: entry.title,
                    source: .history,
                    initialView: resumePoint?.view ?? novel?.lastView,
                    authorID: resumePoint?.authorID ?? novel?.authorID ?? entry.authorID,
                    initialResumePoint: resumePoint
                )
            )

        case let .mangaThread(threadID):
            // A single-thread manga row (recorded while the board was off).
            // If the board is on *now*, resume at the directory level just
            // like a `.mangaThread` favorite would; the next mode-on visit
            // also absorbs this row into a directory-level one (decision
            // #13).
            let smartModeEnabled = await settingsStore.load().isSmartComicModeEnabled(forumID: entry.forumID)
            let ownThreadProgress = await readingProgressStore.load(for: .mangaThread(threadID: threadID))?.manga
            guard smartModeEnabled else {
                return .mangaReader(
                    MangaLaunchContext(
                        originalThreadID: threadID,
                        chapterTID: ownThreadProgress?.chapterThreadID ?? threadID,
                        displayTitle: entry.title,
                        source: .history,
                        chapterView: ownThreadProgress?.chapterView ?? 1,
                        initialPage: ownThreadProgress?.mangaPageIndex ?? 0,
                        directoryName: nil,
                        forumID: entry.forumID,
                        isSmartModeEnabled: false
                    )
                )
            }
            guard let directory = try? await mangaDirectoryStore.directory(containingTID: threadID),
                  let firstChapter = directory.chapters.first else {
                return .mangaReader(
                    MangaLaunchContext(
                        originalThreadID: threadID,
                        chapterTID: ownThreadProgress?.chapterThreadID ?? threadID,
                        displayTitle: entry.title,
                        source: .history,
                        chapterView: ownThreadProgress?.chapterView ?? 1,
                        initialPage: ownThreadProgress?.mangaPageIndex ?? 0,
                        directoryName: nil,
                        forumID: entry.forumID,
                        isSmartModeEnabled: true
                    )
                )
            }
            let directoryTarget = FavoriteContentTarget(
                mangaID: directory.favoriteIdentity,
                mangaCleanBookName: directory.cleanBookName
            )
            let directoryProgress = await readingProgressStore.load(for: directoryTarget)?.manga
            return .mangaReader(
                MangaLaunchContext(
                    originalThreadID: threadID,
                    chapterTID: directoryProgress?.chapterThreadID ?? firstChapter.tid,
                    displayTitle: directory.cleanBookName,
                    source: .history,
                    chapterView: directoryProgress?.chapterView ?? firstChapter.view,
                    initialPage: directoryProgress?.mangaPageIndex ?? 0,
                    directoryName: directory.cleanBookName,
                    forumID: entry.forumID,
                    isSmartModeEnabled: true
                )
            )

        case let .mangaTitle(_, cleanBookName):
            let smartModeEnabled = await settingsStore.load().isSmartComicModeEnabled(forumID: entry.forumID)
            let directoryProgress = await readingProgressStore.load(for: entry.target)?.manga
            guard let chapterTID = directoryProgress?.chapterThreadID ?? entry.chapterThreadID else {
                return nil
            }
            guard smartModeEnabled else {
                // Board toggled off since this directory-level row was
                // written: route by the current switch (PRD compatibility
                // note) — open the row's current chapter as a plain single
                // thread reading its own `.mangaThread` progress.
                let ownThreadProgress = await readingProgressStore.load(for: .mangaThread(threadID: chapterTID))?.manga
                return .mangaReader(
                    MangaLaunchContext(
                        originalThreadID: chapterTID,
                        chapterTID: chapterTID,
                        displayTitle: entry.title,
                        source: .history,
                        chapterView: ownThreadProgress?.chapterView ?? directoryProgress?.chapterView ?? 1,
                        initialPage: ownThreadProgress?.mangaPageIndex ?? 0,
                        directoryName: nil,
                        forumID: entry.forumID,
                        isSmartModeEnabled: false
                    )
                )
            }
            // Progress can have been cleared since this row was written; the
            // chapter's real `view` still matters for multi-view threads, so
            // fall back to the directory's own metadata like the favorites
            // resolver does.
            let fallbackChapterView: Int
            if directoryProgress == nil,
               let directory = try? await mangaDirectoryStore.directory(containingTID: chapterTID) {
                fallbackChapterView = directory.chapters.first { $0.tid == chapterTID }?.view ?? 1
            } else {
                fallbackChapterView = 1
            }
            return .mangaReader(
                MangaLaunchContext(
                    originalThreadID: chapterTID,
                    chapterTID: chapterTID,
                    displayTitle: cleanBookName,
                    source: .history,
                    chapterView: directoryProgress?.chapterView ?? fallbackChapterView,
                    initialPage: directoryProgress?.mangaPageIndex ?? 0,
                    directoryName: cleanBookName,
                    forumID: entry.forumID,
                    isSmartModeEnabled: true
                )
            )
        }
    }
}
