import SwiftUI
import YamiboReaderCore

struct MangaReaderModelDependencies {
    var makeDocumentLoader: @Sendable () async -> any MangaChapterDocumentLoading
    var makeDirectoryRepository: @Sendable () async -> any MangaDirectoryRepository
    var makeDirectoryStore: @Sendable () -> any MangaDirectoryPersisting
    #if os(iOS)
    var makeImageDataLoader: @Sendable () async -> any MangaImageDataLoading
    #endif
    var progressSync: ProgressSyncModule

    #if os(iOS)
    init(
        makeDocumentLoader: @escaping @Sendable () async -> any MangaChapterDocumentLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeDirectoryStore: @escaping @Sendable () -> any MangaDirectoryPersisting,
        makeImageDataLoader: @escaping @Sendable () async -> any MangaImageDataLoading,
        progressSync: ProgressSyncModule
    ) {
        self.makeDocumentLoader = makeDocumentLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeDirectoryStore = makeDirectoryStore
        self.makeImageDataLoader = makeImageDataLoader
        self.progressSync = progressSync
    }
    #else
    init(
        makeDocumentLoader: @escaping @Sendable () async -> any MangaChapterDocumentLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeDirectoryStore: @escaping @Sendable () -> any MangaDirectoryPersisting,
        progressSync: ProgressSyncModule
    ) {
        self.makeDocumentLoader = makeDocumentLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeDirectoryStore = makeDirectoryStore
        self.progressSync = progressSync
    }
    #endif

    init(appContext: YamiboAppContext) {
        #if os(iOS)
        self.init(
            makeDocumentLoader: { await appContext.makeMangaChapterDocumentLoader() },
            makeDirectoryRepository: { await appContext.makeMangaDirectoryRepository() },
            makeDirectoryStore: { appContext.makeMangaDirectoryStore() },
            makeImageDataLoader: { await appContext.makeMangaImageDataLoader() },
            progressSync: ProgressSyncModule(
                adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore)
            )
        )
        #else
        self.init(
            makeDocumentLoader: { await appContext.makeMangaChapterDocumentLoader() },
            makeDirectoryRepository: { await appContext.makeMangaDirectoryRepository() },
            makeDirectoryStore: { appContext.makeMangaDirectoryStore() },
            progressSync: ProgressSyncModule(
                adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore)
            )
        )
        #endif
    }
}

@MainActor
public final class MangaReaderModel: ObservableObject {
    @Published public private(set) var presentation: MangaReaderPresentation

    public let context: MangaLaunchContext
    #if os(iOS)
    private(set) var imagePipeline: MangaImagePipeline?
    #endif

    private let appContext: YamiboAppContext
    private let dependencies: MangaReaderModelDependencies
    private var workflow: MangaReaderWorkflow?
    private var hasPrepared = false
    private var committedSettings = MangaReaderSettings()

    public init(context: MangaLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
        self.dependencies = MangaReaderModelDependencies(appContext: appContext)
        #if os(iOS)
        self.imagePipeline = nil
        #endif
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    init(
        context: MangaLaunchContext,
        appContext: YamiboAppContext,
        dependencies: MangaReaderModelDependencies
    ) {
        self.context = context
        self.appContext = appContext
        self.dependencies = dependencies
        #if os(iOS)
        self.imagePipeline = nil
        #endif
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    public func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        committedSettings = Self.normalizedSettings((await appContext.settingsStore.load()).manga)
        presentation = presentationWithCommittedSettings(presentation)

        #if os(iOS)
        let imagePipeline = MangaImagePipeline(dataLoader: await dependencies.makeImageDataLoader())
        #endif
        let workflow = MangaReaderWorkflow(
            context: context,
            documentLoader: await dependencies.makeDocumentLoader(),
            directoryRepository: await dependencies.makeDirectoryRepository(),
            directoryStore: dependencies.makeDirectoryStore()
        )
        self.workflow = workflow
        #if os(iOS)
        self.imagePipeline = imagePipeline
        #endif
        presentation = presentationWithCommittedSettings(workflow.presentation)
        presentation = presentationWithCommittedSettings(await workflow.prepare())
    }

    public func updateCurrentPage(globalIndex: Int) {
        guard let workflow else { return }
        let nextPresentation = presentationWithCommittedSettings(
            workflow.moveToLoadedPage(at: globalIndex)
        )
        if nextPresentation != presentation {
            presentation = nextPresentation
        }
        scheduleProgressSync(from: nextPresentation)
    }

    public func applySettings(_ settings: MangaReaderSettings) {
        let normalizedSettings = Self.normalizedSettings(settings)
        guard normalizedSettings != committedSettings else { return }

        committedSettings = normalizedSettings
        presentation = presentationWithCommittedSettings(presentation)

        Task { [appContext, normalizedSettings] in
            var appSettings = await appContext.settingsStore.load()
            appSettings.manga = normalizedSettings
            try? await appContext.settingsStore.save(appSettings)
        }
    }

    @discardableResult
    public func saveProgress() async -> MangaPresentationRoute {
        guard let snapshot = progressSnapshot(from: presentation) else {
            return .native(context)
        }

        try? await appContext.readerResumeRouteStore.saveReadingPosition(.manga(snapshot.resumeRoute))
        try? await dependencies.progressSync.flush(.manga(snapshot.progress))
        return snapshot.resumeRoute
    }

    private func scheduleProgressSync(from presentation: MangaReaderPresentation) {
        guard let snapshot = progressSnapshot(from: presentation) else { return }
        let progressSync = dependencies.progressSync
        Task { [appContext, snapshot, progressSync] in
            try? await appContext.readerResumeRouteStore.saveReadingPosition(.manga(snapshot.resumeRoute))
            await progressSync.queue(.manga(snapshot.progress))
        }
    }

    private func progressSnapshot(from presentation: MangaReaderPresentation) -> MangaReaderProgressSnapshot? {
        guard case let .loaded(loaded) = presentation.state,
              let currentPage = loaded.currentPage else {
            return nil
        }

        let progress = MangaProgressReadingPosition(
            threadURL: context.originalThreadURL,
            chapterURL: currentPage.refererURL,
            chapterTitle: currentPage.chapterTitle,
            pageIndex: currentPage.localIndex
        )
        let directoryName = normalizedDirectoryName(loaded.directoryTitle) ?? normalizedDirectoryName(context.directoryName)
        let resumeContext = MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: currentPage.refererURL,
            displayTitle: context.displayTitle,
            source: .resume,
            initialPage: currentPage.localIndex,
            directoryName: directoryName
        )
        return MangaReaderProgressSnapshot(
            progress: progress,
            resumeRoute: .native(resumeContext)
        )
    }

    private func presentationWithCommittedSettings(
        _ presentation: MangaReaderPresentation
    ) -> MangaReaderPresentation {
        var nextPresentation = presentation
        nextPresentation.settings = committedSettings
        return nextPresentation
    }

    private func normalizedDirectoryName(_ directoryName: String?) -> String? {
        let normalized = directoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func normalizedSettings(_ settings: MangaReaderSettings) -> MangaReaderSettings {
        var normalized = settings
        normalized.brightness = normalizedBrightness(settings.brightness)
        return normalized
    }

    private static func normalizedBrightness(_ brightness: Double) -> Double {
        guard brightness.isFinite else { return 1.0 }
        return min(1.5, max(0.25, brightness))
    }

    private static func presentationTitle(for context: MangaLaunchContext) -> String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.string("manga.reader.title") : title
    }
}

private struct MangaReaderProgressSnapshot: Sendable {
    var progress: MangaProgressReadingPosition
    var resumeRoute: MangaPresentationRoute
}
