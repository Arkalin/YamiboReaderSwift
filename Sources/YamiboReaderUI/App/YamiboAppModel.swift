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

    private var webDAVForegroundSyncTask: Task<Void, Never>?
    private var webDAVDebouncedUploadTask: Task<Void, Never>?
    private var isWebDAVSyncInProgress = false

    public init(appContext: YamiboAppContext, initialTab: AppTab = .forum) {
        self.appContext = appContext
        selectedTab = initialTab
    }

    public func bootstrapIfNeeded() async {
        guard bootstrapState == nil, !isBootstrapping else { return }
        await bootstrap()
        synchronizeWebDAVIfNeeded()
    }

    public func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        let state = await appContext.bootstrap()
        bootstrapState = state
        bootstrapErrorMessage = nil
    }

    public func synchronizeWebDAVIfNeeded() {
        webDAVForegroundSyncTask?.cancel()
        webDAVForegroundSyncTask = Task { @MainActor [appContext] in
            guard !isWebDAVSyncInProgress else { return }
            isWebDAVSyncInProgress = true
            defer { isWebDAVSyncInProgress = false }

            do {
                try await appContext.makeWebDAVSyncService().synchronizeAutomatically()
            } catch {
                // Automatic sync should never block the app shell.
            }
        }
    }

    public func scheduleWebDAVUploadForLocalChange() {
        guard !isWebDAVSyncInProgress else { return }
        webDAVDebouncedUploadTask?.cancel()
        webDAVDebouncedUploadTask = Task { @MainActor [appContext] in
            do {
                let service = appContext.makeWebDAVSyncService()
                try await service.markLocalDataChanged()
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
