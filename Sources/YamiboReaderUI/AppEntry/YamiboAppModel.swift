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

    @ObservationIgnored private let appContinuity: AppContinuityWorkflow

    public init(appContext: YamiboAppContext, initialTab: AppTab = .forum) {
        self.appContext = appContext
        selectedTab = initialTab
        appContinuity = AppContinuityWorkflow(appContext: appContext)
    }

    public func bootstrapIfNeeded() async {
        guard bootstrapState == nil, !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        let result = await appContinuity.launchIfNeeded(canRestoreReaderRoute: canRestoreReaderRoute)
        bootstrapState = result.bootstrapState
        bootstrapErrorMessage = nil
        applyRestoredRoute(result.restoredRoute)
    }

    public func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        let state = await appContext.bootstrap()
        bootstrapState = state
        bootstrapErrorMessage = nil
        let restoredRoute = await appContinuity.restoreExplicitly(canRestoreReaderRoute: canRestoreReaderRoute)
        applyRestoredRoute(restoredRoute)
    }

    public func synchronizeWebDAVIfNeeded() {
        appContinuity.foregroundBecameActive()
    }

    public func scheduleWebDAVUploadForLocalChange(touchesAppSettings: Bool = false) {
        appContinuity.localDataChanged(touchesAppSettings: touchesAppSettings)
    }

    public func flushWebDAVSyncBeforeBackground() {
        appContinuity.willEnterBackground()
    }

    public func presentReader(_ context: ReaderLaunchContext) {
        suspendedReaderContext = nil
        activeReaderContext = context
        appContinuity.readerRoutePresented(.novel(context))
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
        appContinuity.readerRoutePresented(.manga(route))
    }

    public func presentMangaWeb(_ context: MangaWebContext) {
        suspendedMangaRoute = nil
        suspendedMangaWebContext = nil
        let route = MangaPresentationRoute.web(context)
        activeMangaRoute = route
        appContinuity.readerRoutePresented(.manga(route))
    }

    public func presentMangaFromWeb(_ context: MangaLaunchContext, preserving webContext: MangaWebContext) {
        suspendedMangaRoute = nil
        suspendedMangaWebContext = webContext.updating(
            autoOpenNative: false,
            waitingForNativeReturn: false
        )
        let route = MangaPresentationRoute.native(context)
        activeMangaRoute = route
        appContinuity.readerRoutePresented(.manga(route))
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
        appContinuity.readerRoutePresented(.manga(route))
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
        appContinuity.readerRoutePresented(.manga(route))
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
        appContinuity.readerRouteDismissed()
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
        appContinuity.readerRouteDismissed()
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
        appContinuity.readerReadingPositionChanged(route)
    }

    private var canRestoreReaderRoute: Bool {
        activeReaderContext == nil && activeMangaRoute == nil
    }

    private func applyRestoredRoute(_ route: ReaderResumeRoute?) {
        guard let route else { return }
        switch route {
        case let .novel(context):
            activeReaderContext = context
        case let .manga(route):
            activeMangaRoute = route
        }
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
