import SwiftUI
import YamiboReaderCore

struct MangaReaderModelDependencies {
    var makeDocumentLoader: @Sendable () async -> any MangaChapterDocumentLoading
    var makeDirectoryRepository: @Sendable () async -> any MangaDirectoryRepository
    var makeDirectoryStore: @Sendable () -> any MangaDirectoryPersisting
    var makeDirectorySearchCooldownState: @Sendable () -> MangaDirectorySearchCooldownState
    var directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration
    #if os(iOS)
    var makeImageDataLoader: @Sendable () async -> any MangaImageDataLoading
    #endif
    var progressSync: ProgressSyncModule

    #if os(iOS)
    init(
        makeDocumentLoader: @escaping @Sendable () async -> any MangaChapterDocumentLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeDirectoryStore: @escaping @Sendable () -> any MangaDirectoryPersisting,
        makeDirectorySearchCooldownState: @escaping @Sendable () -> MangaDirectorySearchCooldownState = {
            MangaDirectorySearchCooldownState()
        },
        directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration = MangaDirectoryWorkflowConfiguration(),
        makeImageDataLoader: @escaping @Sendable () async -> any MangaImageDataLoading,
        progressSync: ProgressSyncModule
    ) {
        self.makeDocumentLoader = makeDocumentLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeDirectoryStore = makeDirectoryStore
        self.makeDirectorySearchCooldownState = makeDirectorySearchCooldownState
        self.directoryWorkflowConfiguration = directoryWorkflowConfiguration
        self.makeImageDataLoader = makeImageDataLoader
        self.progressSync = progressSync
    }
    #else
    init(
        makeDocumentLoader: @escaping @Sendable () async -> any MangaChapterDocumentLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeDirectoryStore: @escaping @Sendable () -> any MangaDirectoryPersisting,
        makeDirectorySearchCooldownState: @escaping @Sendable () -> MangaDirectorySearchCooldownState = {
            MangaDirectorySearchCooldownState()
        },
        directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration = MangaDirectoryWorkflowConfiguration(),
        progressSync: ProgressSyncModule
    ) {
        self.makeDocumentLoader = makeDocumentLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeDirectoryStore = makeDirectoryStore
        self.makeDirectorySearchCooldownState = makeDirectorySearchCooldownState
        self.directoryWorkflowConfiguration = directoryWorkflowConfiguration
        self.progressSync = progressSync
    }
    #endif

    init(appContext: YamiboAppContext) {
        #if os(iOS)
        self.init(
            makeDocumentLoader: { await appContext.makeMangaChapterDocumentLoader() },
            makeDirectoryRepository: { await appContext.makeMangaDirectoryRepository() },
            makeDirectoryStore: { appContext.makeMangaDirectoryStore() },
            makeDirectorySearchCooldownState: { appContext.mangaDirectorySearchCooldownState },
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
            makeDirectorySearchCooldownState: { appContext.mangaDirectorySearchCooldownState },
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
    private var directoryCooldownExpiresAt: Date?
    private var forcedSearchShortcutExpiresAt: Date?
    private var directoryTickTask: Task<Void, Never>?
    private var directoryMutationTask: Task<Void, Never>?
    private var automaticDirectoryUpdateTask: Task<Void, Never>?
    private var chapterJumpTask: Task<Void, Never>?
    private var directoryMutationGeneration = 0
    private var chapterJumpGeneration = 0

    deinit {
        directoryTickTask?.cancel()
        directoryMutationTask?.cancel()
        automaticDirectoryUpdateTask?.cancel()
        chapterJumpTask?.cancel()
    }

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
            directoryStore: dependencies.makeDirectoryStore(),
            settings: committedSettings,
            directoryWorkflowConfiguration: dependencies.directoryWorkflowConfiguration,
            directorySearchCooldownState: dependencies.makeDirectorySearchCooldownState()
        )
        self.workflow = workflow
        #if os(iOS)
        self.imagePipeline = imagePipeline
        #endif
        presentation = workflow.presentation
        presentation = await workflow.prepare()
        refreshDirectoryPanelTiming(errorMessage: nil)
        if workflow.shouldAutoUpdateDirectoryAfterPrepare {
            startAutomaticDirectoryUpdate()
        }
    }

    public func updateCurrentPage(globalIndex: Int) {
        guard let workflow else { return }
        let nextPresentation = workflow.moveToLoadedPage(at: globalIndex)
        if nextPresentation != presentation {
            presentation = nextPresentation
        }
        scheduleProgressSync(from: nextPresentation)
    }

    public func applySettings(_ settings: MangaReaderSettings) {
        let normalizedSettings = Self.normalizedSettings(settings)
        guard normalizedSettings != committedSettings else { return }

        committedSettings = normalizedSettings
        if let workflow {
            presentation = workflow.applySettings(normalizedSettings)
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } else {
            presentation = presentationWithCommittedSettings(presentation)
        }

        Task { [appContext, normalizedSettings] in
            var appSettings = await appContext.settingsStore.load()
            appSettings.manga = normalizedSettings
            try? await appContext.settingsStore.save(appSettings)
        }
    }

    public func updateDirectoryFromPanel() async {
        guard case let .loaded(loaded) = presentation.state else { return }
        await updateDirectory(isForcedSearch: loaded.directoryPanel.shouldForceSearchOnUpdate)
    }

    public func updateDirectory(isForcedSearch: Bool = false) async {
        if isForcedSearch {
            automaticDirectoryUpdateTask?.cancel()
            automaticDirectoryUpdateTask = nil
        }
        await enqueueDirectoryUpdate(isForcedSearch: isForcedSearch, isAutomatic: false)
    }

    public func renameDirectory(cleanBookName: String, searchKeyword: String) async {
        automaticDirectoryUpdateTask?.cancel()
        automaticDirectoryUpdateTask = nil
        directoryMutationTask?.cancel()
        directoryMutationGeneration += 1
        let generation = directoryMutationGeneration
        directoryMutationTask = Task { @MainActor [weak self] in
            await self?.performRenameDirectory(
                cleanBookName: cleanBookName,
                searchKeyword: searchKeyword,
                mutationGeneration: generation
            )
        }
        await directoryMutationTask?.value
    }

    public func renameDirectory(with draft: MangaDirectoryEditDraft) async {
        await renameDirectory(
            cleanBookName: draft.cleanBookName,
            searchKeyword: MangaDirectoryWorkflow.searchKeyword(from: draft)
        )
    }

    public func jumpToChapter(_ chapter: MangaChapter) async {
        chapterJumpTask?.cancel()
        chapterJumpGeneration += 1
        let generation = chapterJumpGeneration
        chapterJumpTask = Task { @MainActor [weak self] in
            await self?.performJumpToChapter(chapter, jumpGeneration: generation)
        }
        await chapterJumpTask?.value
    }

    private func startAutomaticDirectoryUpdate() {
        automaticDirectoryUpdateTask?.cancel()
        automaticDirectoryUpdateTask = Task { @MainActor [weak self] in
            await self?.enqueueDirectoryUpdate(isForcedSearch: false, isAutomatic: true)
        }
    }

    private func enqueueDirectoryUpdate(isForcedSearch: Bool, isAutomatic: Bool) async {
        if isAutomatic, directoryMutationTask != nil {
            automaticDirectoryUpdateTask = nil
            return
        }

        if !isAutomatic {
            directoryMutationTask?.cancel()
        }

        directoryMutationGeneration += 1
        let generation = directoryMutationGeneration
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performDirectoryUpdate(
                isForcedSearch: isForcedSearch,
                isAutomatic: isAutomatic,
                mutationGeneration: generation
            )
        }
        directoryMutationTask = task
        await task.value
    }

    private func performDirectoryUpdate(
        isForcedSearch: Bool,
        isAutomatic: Bool,
        mutationGeneration: Int
    ) async {
        guard let workflow else { return }

        defer {
            if directoryMutationGeneration == mutationGeneration {
                directoryMutationTask = nil
            }
            if isAutomatic {
                automaticDirectoryUpdateTask = nil
            }
        }

        setDirectoryPanelCommandState(isUpdating: true, errorMessage: nil)
        do {
            let result = try await workflow.updateDirectory(isForcedSearch: isForcedSearch)
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            if let cooldownExpiresAt = result.cooldownExpiresAt {
                directoryCooldownExpiresAt = cooldownExpiresAt
                forcedSearchShortcutExpiresAt = nil
            } else if result.shouldOfferForcedSearch {
                directoryCooldownExpiresAt = nil
                forcedSearchShortcutExpiresAt = dependencies.directoryWorkflowConfiguration.now()
                    .addingTimeInterval(dependencies.directoryWorkflowConfiguration.forcedSearchShortcutDuration)
            } else {
                directoryCooldownExpiresAt = nil
                forcedSearchShortcutExpiresAt = nil
            }
            refreshDirectoryPanelTiming(errorMessage: nil)
        } catch is CancellationError {
            guard directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } catch {
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            if case let YamiboError.searchCooldown(seconds) = error {
                directoryCooldownExpiresAt = dependencies.directoryWorkflowConfiguration.now()
                    .addingTimeInterval(TimeInterval(seconds))
                forcedSearchShortcutExpiresAt = nil
            } else if let cooldown = await workflow.currentDirectorySearchCooldownExpiresAt() {
                directoryCooldownExpiresAt = cooldown
                forcedSearchShortcutExpiresAt = nil
            }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
        }
    }

    private func performRenameDirectory(
        cleanBookName: String,
        searchKeyword: String,
        mutationGeneration: Int
    ) async {
        guard let workflow else { return }
        defer {
            if directoryMutationGeneration == mutationGeneration {
                directoryMutationTask = nil
            }
        }

        setDirectoryPanelCommandState(isUpdating: true, errorMessage: nil)
        do {
            _ = try await workflow.renameDirectory(cleanBookName: cleanBookName, searchKeyword: searchKeyword)
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: nil)
        } catch is CancellationError {
            guard directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } catch {
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
        }
    }

    private func performJumpToChapter(_ chapter: MangaChapter, jumpGeneration: Int) async {
        guard let workflow else { return }
        defer {
            if chapterJumpGeneration == jumpGeneration {
                chapterJumpTask = nil
            }
        }

        do {
            let nextPresentation = try await workflow.jumpToChapter(chapter)
            guard !Task.isCancelled, chapterJumpGeneration == jumpGeneration else { return }
            presentation = nextPresentation
            refreshDirectoryPanelTiming(errorMessage: nil)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, chapterJumpGeneration == jumpGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
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

    private var currentDirectoryPanelErrorMessage: String? {
        guard case let .loaded(loaded) = presentation.state else { return nil }
        return loaded.directoryPanel.errorMessage
    }

    private func refreshDirectoryPanelTiming(errorMessage: String?) {
        setDirectoryPanelCommandState(
            isUpdating: false,
            errorMessage: errorMessage
        )
        updateDirectoryTickTask()
    }

    private func setDirectoryPanelCommandState(
        isUpdating: Bool,
        errorMessage: String?
    ) {
        guard let workflow else { return }
        let now = dependencies.directoryWorkflowConfiguration.now()
        let cooldownRemaining = remainingSecondsValue(until: directoryCooldownExpiresAt, now: now)
        let forcedRemaining = remainingSeconds(until: forcedSearchShortcutExpiresAt, now: now)
        if cooldownRemaining == 0 {
            directoryCooldownExpiresAt = nil
        }
        if forcedRemaining == nil {
            forcedSearchShortcutExpiresAt = nil
        }
        presentation = workflow.updateDirectoryPanelCommandState(
            MangaDirectoryPanelCommandState(
                isUpdating: isUpdating,
                cooldownRemaining: cooldownRemaining,
                forcedSearchShortcutRemaining: forcedRemaining,
                errorMessage: errorMessage
            )
        )
    }

    private func updateDirectoryTickTask() {
        let hasActiveDeadline = directoryCooldownExpiresAt != nil || forcedSearchShortcutExpiresAt != nil
        guard hasActiveDeadline else {
            directoryTickTask?.cancel()
            directoryTickTask = nil
            return
        }
        guard directoryTickTask == nil else { return }

        directoryTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.setDirectoryPanelCommandState(
                    isUpdating: false,
                    errorMessage: self?.currentDirectoryPanelErrorMessage
                )
                guard self?.directoryCooldownExpiresAt != nil || self?.forcedSearchShortcutExpiresAt != nil else {
                    self?.directoryTickTask = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func remainingSeconds(until deadline: Date?, now: Date) -> Int? {
        guard let deadline else { return nil }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return max(1, Int(ceil(remaining)))
    }

    private func remainingSecondsValue(until deadline: Date?, now: Date) -> Int {
        remainingSeconds(until: deadline, now: now) ?? 0
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
