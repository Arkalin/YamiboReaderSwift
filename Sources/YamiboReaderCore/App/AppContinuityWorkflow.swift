import Foundation

public struct AppContinuityLaunchResult: Sendable {
    public let bootstrapState: YamiboBootstrapState
    public let restoredRoute: ReaderResumeRoute?

    public init(bootstrapState: YamiboBootstrapState, restoredRoute: ReaderResumeRoute?) {
        self.bootstrapState = bootstrapState
        self.restoredRoute = restoredRoute
    }
}

@MainActor
public final class AppContinuityWorkflow {
    private let appContext: YamiboAppContext
    private var foregroundSyncTask: Task<Void, Never>?
    private var debouncedUploadTask: Task<Void, Never>?
    private var isWebDAVSyncInProgress = false
    private var hasRestoredReaderResumeRoute = false
    private var isReaderRoutePresented = false

    public init(appContext: YamiboAppContext) {
        self.appContext = appContext
    }

    public func launchIfNeeded(canRestoreReaderRoute: Bool) async -> AppContinuityLaunchResult {
        let bootstrapState = await appContext.bootstrap()
        let didDownloadRemoteProgress = await synchronizeWebDAVForStartup()
        let restoredRoute = await restoreExplicitly(
            canRestoreReaderRoute: canRestoreReaderRoute,
            reconcilesWithReadingProgress: didDownloadRemoteProgress
        )
        return AppContinuityLaunchResult(bootstrapState: bootstrapState, restoredRoute: restoredRoute)
    }

    public func restoreExplicitly(
        canRestoreReaderRoute: Bool,
        reconcilesWithReadingProgress: Bool = false
    ) async -> ReaderResumeRoute? {
        guard !hasRestoredReaderResumeRoute else { return nil }
        hasRestoredReaderResumeRoute = true
        guard canRestoreReaderRoute else { return nil }
        guard let route = await appContext.readerResumeRouteStore.load() else { return nil }

        guard let restoredRoute = await restorableRoute(
            from: route,
            reconcilesWithReadingProgress: reconcilesWithReadingProgress
        ) else {
            await appContext.readerResumeRouteStore.clear()
            return nil
        }

        if restoredRoute != route {
            try? await appContext.readerResumeRouteStore.save(restoredRoute)
        }
        isReaderRoutePresented = true
        return restoredRoute
    }

    public func foregroundBecameActive() {
        foregroundSyncTask?.cancel()
        foregroundSyncTask = Task { @MainActor [weak self] in
            _ = await self?.synchronizeWebDAVSilently()
        }
    }

    public func localDataChanged(touchesAppSettings: Bool = false) {
        guard !isWebDAVSyncInProgress else { return }
        debouncedUploadTask?.cancel()
        debouncedUploadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let service = appContext.makeWebDAVSyncService()
                try await service.markLocalDataChanged(touchesAppSettings: touchesAppSettings)
                try await Task.sleep(for: .seconds(2))

                guard !isWebDAVSyncInProgress else { return }
                isWebDAVSyncInProgress = true
                defer { isWebDAVSyncInProgress = false }

                try await service.synchronizeAutomatically()
            } catch {
                // Keep local data authoritative until the next foreground or manual sync.
            }
        }
    }

    public func willEnterBackground() {
        debouncedUploadTask?.cancel()
        debouncedUploadTask = nil
        Task { @MainActor [weak self] in
            await self?.flushWebDAVSyncBeforeBackground()
        }
    }

    public func readerRoutePresented(_ route: ReaderResumeRoute) {
        isReaderRoutePresented = true
        Task { [appContext] in
            try? await appContext.readerResumeRouteStore.save(route)
        }
    }

    public func readerRouteDismissed() {
        isReaderRoutePresented = false
        appContext.readerResumeRouteStore.clearSync()
    }

    public func readerReadingPositionChanged(_ route: ReaderResumeRoute) {
        guard isReaderRoutePresented else { return }
        Task { [appContext] in
            try? await appContext.readerResumeRouteStore.saveReadingPosition(route)
        }
    }

    private func synchronizeWebDAVForStartup() async -> Bool {
        foregroundSyncTask?.cancel()
        foregroundSyncTask = nil
        let result = await synchronizeWebDAVSilently()
        if case .downloaded = result {
            return true
        }
        return false
    }

    private func synchronizeWebDAVSilently() async -> WebDAVAutomaticSyncResult {
        guard !isWebDAVSyncInProgress else { return .skipped }
        isWebDAVSyncInProgress = true
        defer { isWebDAVSyncInProgress = false }

        do {
            return try await appContext.makeWebDAVSyncService().synchronizeAutomatically()
        } catch {
            // Automatic sync should never block the app shell.
            return .skipped
        }
    }

    private func flushWebDAVSyncBeforeBackground() async {
        guard !isWebDAVSyncInProgress else { return }
        isWebDAVSyncInProgress = true
        defer { isWebDAVSyncInProgress = false }

        do {
            try await appContext.makeWebDAVSyncService().synchronizeAutomatically()
        } catch {
            // Background flush is best effort.
        }
    }

    private func restorableRoute(
        from route: ReaderResumeRoute,
        reconcilesWithReadingProgress: Bool
    ) async -> ReaderResumeRoute? {
        if reconcilesWithReadingProgress {
            if let route = await routeReconciledWithReadingProgress(route) {
                return route
            }
        }
        if route.hasLocalReadingProgress {
            return route
        }
        if !reconcilesWithReadingProgress {
            return await routeReconciledWithReadingProgress(route)
        }
        return nil
    }

    private func routeReconciledWithReadingProgress(_ route: ReaderResumeRoute) async -> ReaderResumeRoute? {
        switch route {
        case let .novel(context):
            if let progress = await appContext.readingProgressStore.load(threadID: context.threadID),
               progress.hasNovelReadingProgress {
                return .novel(context.reconciledWithReadingProgress(
                    progress,
                    favoriteItem: await favoriteItem(forThreadID: context.threadID)
                ))
            }
            return nil
        case let .manga(context):
            if let progress = await appContext.readingProgressStore.load(threadID: context.originalThreadID),
               progress.hasMangaReadingProgress {
                return .manga(context.reconciledWithReadingProgress(
                    progress,
                    favoriteItem: await favoriteItem(forMangaContext: context)
                ))
            }
            return nil
        }
    }

    private func favoriteItem(forThreadID threadID: String) async -> FavoriteItem? {
        let target = FavoriteContentTarget.novelThread(threadID: threadID)
        return await appContext.localFavoriteLibraryStore.load().items.first { item in
            item.target.id == target.id || item.target.threadID == target.threadID
        }
    }

    private func favoriteItem(forMangaContext context: MangaLaunchContext) async -> FavoriteItem? {
        let document = await appContext.localFavoriteLibraryStore.load()
        if let directoryName = context.directoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directoryName.isEmpty {
            let target = FavoriteContentTarget(mangaCleanBookName: directoryName)
            if let item = document.items.first(where: { $0.target.id == target.id }) {
                return item
            }
        }
        return document.items.first { item in
            item.target.threadID == context.originalThreadID || item.mangaChapterMetadata?.chapterTID == context.chapterTID
        }
    }
}

private extension ReaderResumeRoute {
    var hasLocalReadingProgress: Bool {
        switch self {
        case let .novel(context):
            context.hasLocalReadingProgress
        case let .manga(context):
            context.hasLocalReadingProgress
        }
    }
}

private extension NovelLaunchContext {
    var hasLocalReadingProgress: Bool {
        initialResumePoint != nil || (initialView ?? 1) > 1
    }
}

private extension MangaLaunchContext {
    var hasLocalReadingProgress: Bool {
        initialPage > 0 || chapterTID != originalThreadID || chapterView > 1
    }
}

private extension ReadingProgressRecord {
    var hasNovelReadingProgress: Bool {
        guard let novel else { return false }
        return novel.novelResumePoint != nil ||
            novel.lastView > 1 ||
            novel.lastChapter != nil ||
            novel.authorID != nil ||
            novel.novelMaxView != nil ||
            novel.novelDocumentSurfaceProgressPercent != nil
    }

    var hasMangaReadingProgress: Bool {
        manga != nil
    }
}

private extension NovelLaunchContext {
    func reconciledWithReadingProgress(
        _ progress: ReadingProgressRecord,
        favoriteItem: FavoriteItem?
    ) -> NovelLaunchContext {
        let novel = progress.novel
        let resumePoint = novel?.novelResumePoint ?? initialResumePoint
        return NovelLaunchContext(
            threadID: threadID,
            threadTitle: favoriteItem?.resolvedDisplayTitle ?? threadTitle,
            source: .resume,
            initialView: resumePoint?.view ?? novel?.lastView ?? initialView,
            authorID: resumePoint?.authorID ?? novel?.authorID ?? authorID,
            initialResumePoint: resumePoint
        )
    }
}

private extension MangaLaunchContext {
    func reconciledWithReadingProgress(
        _ progress: ReadingProgressRecord,
        favoriteItem: FavoriteItem?
    ) -> MangaLaunchContext {
        guard let manga = progress.manga else { return self }
        return MangaLaunchContext(
            originalThreadID: originalThreadID,
            chapterTID: manga.chapterThreadID,
            displayTitle: favoriteItem?.resolvedDisplayTitle ?? displayTitle,
            source: .resume,
            chapterView: manga.chapterView,
            initialPage: manga.mangaPageIndex,
            directoryName: directoryName,
            offlineCacheFavoriteID: favoriteItem?.id ?? offlineCacheFavoriteID
        )
    }
}
