import Foundation
import Observation
import YamiboReaderCore

public struct ForumNavigationRequest: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

@MainActor
@Observable
public final class YamiboAppModel {
    public private(set) var bootstrapState: YamiboBootstrapState?
    public private(set) var isBootstrapping = false
    public var bootstrapErrorMessage: String?
    public private(set) var selectedTab: AppTab
    public var activeReaderContext: ReaderLaunchContext?
    public var activeMangaRoute: MangaPresentationRoute?
    public private(set) var suspendedReaderContext: ReaderLaunchContext?
    public private(set) var suspendedMangaRoute: MangaPresentationRoute?
    public private(set) var suspendedMangaWebContext: MangaWebContext?
    public private(set) var forumNavigationRequest: ForumNavigationRequest?

    public let appContext: YamiboAppContext

    private var webDAVForegroundSyncTask: Task<Void, Never>?
    private var webDAVDebouncedUploadTask: Task<Void, Never>?
    private var isWebDAVSyncInProgress = false
    private var hasRestoredReaderResumeRoute = false

    public init(appContext: YamiboAppContext, initialTab: AppTab = .forum) {
        self.appContext = appContext
        selectedTab = initialTab
    }

    public func bootstrapIfNeeded() async {
        guard bootstrapState == nil, !isBootstrapping else { return }
        await bootstrap(restoresReaderResumeRoute: false)
        let didDownloadRemoteProgress = await synchronizeWebDAVForStartup()
        await restoreReaderResumeRouteIfNeeded(reconcilesWithFavoriteProgress: didDownloadRemoteProgress)
    }

    public func bootstrap() async {
        await bootstrap(restoresReaderResumeRoute: true)
    }

    private func bootstrap(restoresReaderResumeRoute: Bool) async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        let state = await appContext.bootstrap()
        bootstrapState = state
        bootstrapErrorMessage = nil
        if restoresReaderResumeRoute {
            await restoreReaderResumeRouteIfNeeded()
        }
    }

    public func synchronizeWebDAVIfNeeded() {
        webDAVForegroundSyncTask?.cancel()
        webDAVForegroundSyncTask = Task { @MainActor [weak self] in
            _ = await self?.synchronizeWebDAVSilently()
        }
    }

    private func synchronizeWebDAVForStartup() async -> Bool {
        webDAVForegroundSyncTask?.cancel()
        webDAVForegroundSyncTask = nil
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

    public func scheduleWebDAVUploadForLocalChange(touchesAppSettings: Bool = false) {
        guard !isWebDAVSyncInProgress else { return }
        webDAVDebouncedUploadTask?.cancel()
        webDAVDebouncedUploadTask = Task { @MainActor [appContext, touchesAppSettings] in
            do {
                let service = appContext.makeWebDAVSyncService()
                try await service.markLocalDataChanged(touchesAppSettings: touchesAppSettings)
                try await Task.sleep(for: .seconds(2))

                guard !isWebDAVSyncInProgress else { return }
                isWebDAVSyncInProgress = true
                defer { isWebDAVSyncInProgress = false }

                try await service.synchronizeAutomatically()
            } catch {
                // Keep local data authoritative until the next foreground/manual sync.
            }
        }
    }

    public func flushWebDAVSyncBeforeBackground() {
        webDAVDebouncedUploadTask?.cancel()
        webDAVDebouncedUploadTask = nil
        Task { @MainActor [appContext] in
            guard !isWebDAVSyncInProgress else { return }
            isWebDAVSyncInProgress = true
            defer { isWebDAVSyncInProgress = false }

            do {
                try await appContext.makeWebDAVSyncService().synchronizeAutomatically()
            } catch {
                // Background flush is best effort.
            }
        }
    }

    public func presentReader(_ context: ReaderLaunchContext) {
        suspendedReaderContext = nil
        activeReaderContext = context
        persistReaderResumeRoute(.novel(context))
    }

    public func selectTab(_ tab: AppTab) {
        selectedTab = tab
        restoreSuspendedReaderIfNeeded(for: tab)
        restoreSuspendedMangaIfNeeded(for: tab)
    }

    public func presentManga(_ context: MangaLaunchContext) {
        suspendedMangaRoute = nil
        suspendedMangaWebContext = nil
        let route = MangaPresentationRoute.native(context)
        activeMangaRoute = route
        persistReaderResumeRoute(.manga(route))
    }

    public func presentMangaWeb(_ context: MangaWebContext) {
        suspendedMangaRoute = nil
        suspendedMangaWebContext = nil
        let route = MangaPresentationRoute.web(context)
        activeMangaRoute = route
        persistReaderResumeRoute(.manga(route))
    }

    public func presentMangaFromWeb(_ context: MangaLaunchContext, preserving webContext: MangaWebContext) {
        suspendedMangaRoute = nil
        suspendedMangaWebContext = webContext.updating(
            autoOpenNative: false,
            waitingForNativeReturn: false
        )
        let route = MangaPresentationRoute.native(context)
        activeMangaRoute = route
        persistReaderResumeRoute(.manga(route))
    }

    public func fallbackMangaToWeb(_ context: MangaWebContext) {
        suspendedMangaRoute = nil
        suspendedMangaWebContext = nil
        let route = MangaPresentationRoute.web(
            context.updating(
                autoOpenNative: false,
                waitingForNativeReturn: false
            )
        )
        activeMangaRoute = route
        persistReaderResumeRoute(.manga(route))
    }

    public func dismissMangaRestoringWebIfNeeded() {
        guard let suspendedMangaWebContext else {
            dismissManga()
            return
        }
        suspendedMangaRoute = nil
        self.suspendedMangaWebContext = nil
        let route = MangaPresentationRoute.web(
            suspendedMangaWebContext.updating(
                autoOpenNative: false,
                waitingForNativeReturn: true
            )
        )
        activeMangaRoute = route
        persistReaderResumeRoute(.manga(route))
    }

    public func openManga(_ context: MangaLaunchContext, currentHTML: String? = nil, currentTitle: String? = nil) async {
        _ = currentHTML
        _ = currentTitle
        presentManga(context)
    }

    public func dismissReader(openThreadInForum url: URL? = nil, suspendedContext: ReaderLaunchContext? = nil) {
        if url != nil {
            suspendedReaderContext = suspendedContext ?? activeReaderContext
        } else {
            suspendedReaderContext = nil
        }
        activeReaderContext = nil
        clearReaderResumeRoute()
        if let url {
            selectedTab = .forum
            forumNavigationRequest = ForumNavigationRequest(url: url)
        }
    }

    public func dismissManga(
        openThreadInForum url: URL? = nil,
        suspendedRoute: MangaPresentationRoute? = nil
    ) {
        if url != nil {
            suspendedMangaRoute = suspendedRoute ?? activeMangaRoute
        } else if activeMangaRoute != nil {
            suspendedMangaRoute = nil
        }
        activeMangaRoute = nil
        suspendedMangaWebContext = nil
        clearReaderResumeRoute()
        if let url {
            selectedTab = .forum
            forumNavigationRequest = ForumNavigationRequest(url: url)
        }
    }

    public func updateReaderResumeRoute(_ route: ReaderResumeRoute) {
        switch route {
        case let .novel(context):
            guard activeReaderContext != nil else { return }
            activeReaderContext = context
        case let .manga(route):
            guard activeMangaRoute != nil else { return }
            activeMangaRoute = route
        }
        persistReaderResumePosition(route)
    }

    private func restoreReaderResumeRouteIfNeeded(reconcilesWithFavoriteProgress: Bool = false) async {
        guard !hasRestoredReaderResumeRoute else { return }
        hasRestoredReaderResumeRoute = true
        guard activeReaderContext == nil, activeMangaRoute == nil else { return }
        guard let route = await appContext.readerResumeRouteStore.load() else { return }
        let restoredRoute = if reconcilesWithFavoriteProgress {
            await routeReconciledWithFavoriteProgress(route)
        } else {
            route
        }
        if restoredRoute != route {
            try? await appContext.readerResumeRouteStore.save(restoredRoute)
        }

        switch restoredRoute {
        case let .novel(context):
            activeReaderContext = context
        case let .manga(route):
            activeMangaRoute = route
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

    private func persistReaderResumeRoute(_ route: ReaderResumeRoute) {
        Task { [appContext] in
            try? await appContext.readerResumeRouteStore.save(route)
        }
    }

    private func persistReaderResumePosition(_ route: ReaderResumeRoute) {
        Task { [appContext] in
            try? await appContext.readerResumeRouteStore.saveReadingPosition(route)
        }
    }

    private func clearReaderResumeRoute() {
        appContext.readerResumeRouteStore.clearSync()
    }

    private func restoreSuspendedReaderIfNeeded(for tab: AppTab) {
        guard tab == .favorites, let context = suspendedReaderContext else { return }
        suspendedReaderContext = nil
        activeReaderContext = context
    }

    private func restoreSuspendedMangaIfNeeded(for tab: AppTab) {
        guard tab == .favorites, let route = suspendedMangaRoute else { return }
        suspendedMangaRoute = nil
        activeMangaRoute = route
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
