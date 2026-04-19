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
    public var selectedTab: AppTab
    public var activeReaderContext: ReaderLaunchContext?
    public var activeMangaRoute: MangaPresentationRoute?
    public private(set) var suspendedMangaWebContext: MangaWebContext?
    public private(set) var forumNavigationRequest: ForumNavigationRequest?

    public let appContext: YamiboAppContext

    public init(appContext: YamiboAppContext, initialTab: AppTab = .forum) {
        self.appContext = appContext
        selectedTab = initialTab
    }

    public func bootstrapIfNeeded() async {
        guard bootstrapState == nil, !isBootstrapping else { return }
        await bootstrap()
    }

    public func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        let state = await appContext.bootstrap()
        bootstrapState = state
        bootstrapErrorMessage = nil
    }

    public func presentReader(_ context: ReaderLaunchContext) {
        activeReaderContext = context
    }

    public func presentManga(_ context: MangaLaunchContext) {
        suspendedMangaWebContext = nil
        activeMangaRoute = .native(context)
    }

    public func presentMangaWeb(_ context: MangaWebContext) {
        suspendedMangaWebContext = nil
        activeMangaRoute = .web(context)
    }

    public func presentMangaFromWeb(_ context: MangaLaunchContext, preserving webContext: MangaWebContext) {
        suspendedMangaWebContext = webContext.updating(
            autoOpenNative: false,
            waitingForNativeReturn: false
        )
        activeMangaRoute = .native(context)
    }

    public func fallbackMangaToWeb(_ context: MangaWebContext) {
        suspendedMangaWebContext = nil
        activeMangaRoute = .web(
            context.updating(
                autoOpenNative: false,
                waitingForNativeReturn: false
            )
        )
    }

    public func dismissMangaRestoringWebIfNeeded() {
        guard let suspendedMangaWebContext else {
            dismissManga()
            return
        }
        self.suspendedMangaWebContext = nil
        activeMangaRoute = .web(
            suspendedMangaWebContext.updating(
                autoOpenNative: false,
                waitingForNativeReturn: true
            )
        )
    }

    public func openManga(_ context: MangaLaunchContext, currentHTML: String? = nil, currentTitle: String? = nil) async {
        let probeService = MangaProbeService(appContext: appContext)
        let outcome = await probeService.probe(
            launchContext: context,
            currentHTML: currentHTML,
            currentTitle: currentTitle
        )
        switch outcome {
        case .success:
            presentManga(context)
        case let .fallback(_, suggestedWebContext):
            suspendedMangaWebContext = nil
            presentMangaWeb(suggestedWebContext)
        }
    }

    public func dismissReader(openThreadInForum url: URL? = nil) {
        activeReaderContext = nil
        if let url {
            selectedTab = .forum
            forumNavigationRequest = ForumNavigationRequest(url: url)
        }
    }

    public func dismissManga(openThreadInForum url: URL? = nil) {
        activeMangaRoute = nil
        suspendedMangaWebContext = nil
        if let url {
            selectedTab = .forum
            forumNavigationRequest = ForumNavigationRequest(url: url)
        }
    }
}
