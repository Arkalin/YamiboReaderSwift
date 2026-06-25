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
            reconcilesWithFavoriteProgress: didDownloadRemoteProgress
        )
        return AppContinuityLaunchResult(bootstrapState: bootstrapState, restoredRoute: restoredRoute)
    }

    public func restoreExplicitly(
        canRestoreReaderRoute: Bool,
        reconcilesWithFavoriteProgress: Bool = false
    ) async -> ReaderResumeRoute? {
        guard !hasRestoredReaderResumeRoute else { return nil }
        hasRestoredReaderResumeRoute = true
        guard canRestoreReaderRoute else { return nil }
        guard let route = await appContext.readerResumeRouteStore.load() else { return nil }

        let restoredRoute = if reconcilesWithFavoriteProgress {
            await routeReconciledWithFavoriteProgress(route)
        } else {
            route
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

    private func routeReconciledWithFavoriteProgress(_ route: ReaderResumeRoute) async -> ReaderResumeRoute {
        switch route {
        case let .novel(context):
            guard let favorite = await appContext.favoriteStore.favorite(for: context.threadURL),
                  favorite.hasNovelReadingProgress
            else {
                return route
            }
            return .novel(context.reconciledWithFavoriteProgress(favorite))
        case let .manga(route):
            let route = await mangaRouteReconciledWithFavoriteProgress(route)
            return .manga(route)
        }
    }

    private func mangaRouteReconciledWithFavoriteProgress(_ route: MangaPresentationRoute) async -> MangaPresentationRoute {
        switch route {
        case let .native(context):
            guard let favorite = await appContext.favoriteStore.favorite(for: context.originalThreadURL),
                  favorite.hasMangaReadingProgress
            else {
                return route
            }
            return .native(context.reconciledWithFavoriteProgress(favorite))
        case let .web(context):
            guard let favorite = await appContext.favoriteStore.favorite(for: context.originalThreadURL),
                  favorite.hasMangaReadingProgress
            else {
                return route
            }
            return .web(context.reconciledWithFavoriteProgress(favorite))
        }
    }
}

private extension Favorite {
    var hasNovelReadingProgress: Bool {
        novelResumePoint != nil ||
            lastView > 1 ||
            lastChapter != nil ||
            authorID != nil ||
            novelMaxView != nil
    }

    var hasMangaReadingProgress: Bool {
        lastMangaURL != nil ||
            mangaPageIndex > 0 ||
            type == .manga
    }
}

private extension ReaderLaunchContext {
    func reconciledWithFavoriteProgress(_ favorite: Favorite) -> ReaderLaunchContext {
        let resumePoint = favorite.novelResumePoint ?? initialResumePoint
        return ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: favorite.resolvedDisplayTitle,
            source: .resume,
            initialView: resumePoint?.view ?? favorite.lastView,
            authorID: resumePoint?.authorID ?? favorite.authorID ?? authorID,
            initialResumePoint: resumePoint
        )
    }
}

private extension MangaLaunchContext {
    func reconciledWithFavoriteProgress(_ favorite: Favorite) -> MangaLaunchContext {
        MangaLaunchContext(
            originalThreadURL: originalThreadURL,
            chapterURL: favorite.lastMangaURL ?? chapterURL,
            displayTitle: favorite.resolvedDisplayTitle,
            source: .resume,
            initialPage: favorite.mangaPageIndex,
            directoryName: directoryName
        )
    }
}

private extension MangaWebContext {
    func reconciledWithFavoriteProgress(_ favorite: Favorite) -> MangaWebContext {
        MangaWebContext(
            currentURL: favorite.lastMangaURL ?? currentURL,
            originalThreadURL: originalThreadURL,
            source: .resume,
            initialPage: favorite.mangaPageIndex,
            autoOpenNative: autoOpenNative,
            waitingForNativeReturn: waitingForNativeReturn
        )
    }
}
