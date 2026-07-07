import Foundation
import UIKit
import YamiboReaderCore

/// State machine for one Yamibo remote favorite sync run. The five-phase
/// engine (`FavoriteYamiboSyncEngine`) does the actual work; this session
/// owns task lifecycle, background-task extension, and snapshot persistence
/// through `FavoriteSyncRunStore`.
///
/// Library changes are written through the shared `FavoriteLibraryStore`,
/// whose change notification lets `FavoriteLibraryOrganizer` refresh itself;
/// this session never touches the organizer directly.
@MainActor
final class FavoriteRemoteSyncSession: ObservableObject {
    /// Runs the sync for one snapshot, reporting progress through the persist
    /// callback and returning the terminal snapshot. Tests inject a fake.
    typealias EngineRunner = @Sendable (
        _ snapshot: FavoriteRemoteSyncSnapshot,
        _ interruptionReason: @escaping @Sendable () -> FavoriteRemoteSyncWarning?,
        _ persist: @escaping @Sendable (FavoriteRemoteSyncSnapshot) async -> Void
    ) async -> FavoriteRemoteSyncSnapshot

    @Published private(set) var snapshot: FavoriteRemoteSyncSnapshot?
    @Published var errorMessage: String?

    private let libraryStore: FavoriteLibraryStore
    private let runStore: FavoriteSyncRunStore
    private let contentCoverStore: ContentCoverStore
    private let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    private let makeForumThreadReaderRepository: @Sendable () async -> ForumThreadReaderRepository
    private let makeThreadRouteResolver: @Sendable () async -> YamiboThreadRouteResolver
    private let runnerOverride: EngineRunner?
    private let interruptionReasonBox = FavoriteSyncInterruptionReasonBox()

    private var syncTask: Task<Void, Never>?
#if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
#endif

    private static var activeRunCancelHandlers: [String: () -> Void] = [:]

    static func isRunActive(_ runID: String) -> Bool {
        activeRunCancelHandlers[runID] != nil
    }

    init(
        libraryStore: FavoriteLibraryStore,
        runStore: FavoriteSyncRunStore,
        contentCoverStore: ContentCoverStore,
        makeFavoriteRepository: @escaping @Sendable () async -> FavoriteRepository,
        makeForumThreadReaderRepository: @escaping @Sendable () async -> ForumThreadReaderRepository,
        makeThreadRouteResolver: @escaping @Sendable () async -> YamiboThreadRouteResolver,
        runnerOverride: EngineRunner? = nil
    ) {
        self.libraryStore = libraryStore
        self.runStore = runStore
        self.contentCoverStore = contentCoverStore
        self.makeFavoriteRepository = makeFavoriteRepository
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.makeThreadRouteResolver = makeThreadRouteResolver
        self.runnerOverride = runnerOverride
    }

    deinit {
        syncTask?.cancel()
    }

    /// Restores the persisted snapshot; a snapshot still marked running whose
    /// task no longer exists is downgraded to interrupted.
    func load() async {
        snapshot = await interruptedSnapshotIfNeeded(runStore.latestSnapshot())
    }

    @discardableResult
    func start(targetCategoryID: String) async -> String? {
        if snapshot?.status == .running {
            return snapshot?.runID
        }

        let document = await libraryStore.load()
        let categoryName = document.categories.first { $0.id == targetCategoryID }?.displayName
            ?? document.defaultCategory.displayName
        let now = Date()
        var startedSnapshot = FavoriteRemoteSyncSnapshot(
            status: .running,
            targetCategoryID: targetCategoryID,
            targetCategoryName: categoryName,
            phase: .queued,
            startedAt: now,
            updatedAt: now,
            logEntries: [.started(categoryName: categoryName)]
        )
        interruptionReasonBox.set(nil)
        let backgroundTaskAvailable = beginBackgroundTask(runID: startedSnapshot.runID)
        if !backgroundTaskAvailable {
            startedSnapshot.warnings.append(.backgroundUnavailable)
        }
        snapshot = startedSnapshot
        await persistSnapshot(startedSnapshot)

        syncTask?.cancel()
        let runSnapshot = startedSnapshot
        syncTask = Task { @MainActor [weak self] in
            await self?.run(startSnapshot: runSnapshot)
        }
        Self.activeRunCancelHandlers[startedSnapshot.runID] = { [weak self] in
            self?.syncTask?.cancel()
        }
        return startedSnapshot.runID
    }

    @discardableResult
    func resume() async -> String? {
        guard let snapshot else { return nil }
        return await start(targetCategoryID: snapshot.targetCategoryID)
    }

    func interrupt() async {
        guard snapshot?.status == .running else { return }
        interruptionReasonBox.set(.interruptedByUser)
        syncTask?.cancel()
    }

    func hideCard() async {
        guard var snapshot else { return }
        snapshot.isHiddenFromFavoritePage = true
        self.snapshot = snapshot
        await persistSnapshot(snapshot)
    }

    // MARK: - Run

    private func run(startSnapshot: FavoriteRemoteSyncSnapshot) async {
        let runID = startSnapshot.runID
        defer {
            endBackgroundTask()
            Self.activeRunCancelHandlers[runID] = nil
        }

        let runner = runnerOverride ?? makeEngineRunner()
        let interruptionReason: @Sendable () -> FavoriteRemoteSyncWarning? = { [interruptionReasonBox] in
            interruptionReasonBox.take()
        }
        let persist: @Sendable (FavoriteRemoteSyncSnapshot) async -> Void = { [weak self] updated in
            await self?.applyEngineSnapshot(updated)
        }
        let final = await runner(startSnapshot, interruptionReason, persist)
        switch final.status {
        case .completed:
            errorMessage = nil
        case .failed:
            errorMessage = final.errorMessages.last
        case .running, .interrupted:
            break
        }
    }

    /// Merges an engine-produced snapshot with session-owned presentation
    /// state (card hiding), persists it, then publishes it. Persist-first
    /// keeps the published state from ever running ahead of the stored one.
    private func applyEngineSnapshot(_ updated: FavoriteRemoteSyncSnapshot) async {
        var merged = updated
        if let current = snapshot, current.runID == updated.runID {
            merged.isHiddenFromFavoritePage = current.isHiddenFromFavoritePage
        }
        await persistSnapshot(merged)
        snapshot = merged
    }

    private func makeEngineRunner() -> EngineRunner {
        let libraryStore = libraryStore
        let contentCoverStore = contentCoverStore
        let makeFavoriteRepository = makeFavoriteRepository
        let makeForumThreadReaderRepository = makeForumThreadReaderRepository
        let makeThreadRouteResolver = makeThreadRouteResolver
        return { snapshot, interruptionReason, persist in
            let repository = await makeFavoriteRepository()
            let resolver = await makeThreadRouteResolver()
            let coverRepository = await makeForumThreadReaderRepository()
            let formHashBox = FavoriteSyncFormHashBox()
            let client = FavoriteYamiboSyncClient(
                fetchPage: { page in
                    let result = try await repository.fetchFavoritesPage(page: page)
                    let entries = result.favorites.map { favorite in
                        YamiboRemoteFavoriteEntry(
                            remoteFavoriteID: favorite.remoteFavoriteID ?? favorite.id,
                            threadID: favorite.threadID,
                            title: favorite.title
                        )
                    }
                    return FavoriteYamiboRemotePage(
                        entries: entries,
                        currentPage: result.currentPage,
                        totalPages: result.totalPages
                    )
                },
                probe: { entry in
                    let result = try await Self.probeResult(
                        forThreadID: entry.threadID,
                        title: entry.title,
                        resolver: resolver,
                        coverRepository: coverRepository
                    )
                    if let coverURL = result.coverURL, let key = ContentCoverKey(target: result.target) {
                        _ = try? await contentCoverStore.setAutomaticCover(coverURL, for: key)
                    }
                    return result
                },
                addFavorite: { threadID in
                    let formHash = try await formHashBox.formHash(repository: repository)
                    _ = try await repository.addThreadFavorite(
                        threadID: threadID,
                        formHash: formHash,
                        resolveRemoteFavorite: false
                    )
                }
            )
            let engine = FavoriteYamiboSyncEngine(libraryStore: libraryStore, client: client)
            return await engine.run(
                snapshot: snapshot,
                interruptionReason: interruptionReason,
                persist: persist
            )
        }
    }

    // MARK: - Snapshot state

    private func interruptedSnapshotIfNeeded(_ snapshot: FavoriteRemoteSyncSnapshot?) async -> FavoriteRemoteSyncSnapshot? {
        guard var snapshot else { return nil }
        guard snapshot.status == .running else { return snapshot }
        guard !Self.isRunActive(snapshot.runID) else { return snapshot }
        snapshot.status = .interrupted
        snapshot.phase = .interrupted
        snapshot.finishedAt = snapshot.finishedAt ?? .now
        snapshot.updatedAt = .now
        snapshot.warnings.append(.taskLost)
        snapshot.logEntries.append(.taskLost)
        await persistSnapshot(snapshot)
        return snapshot
    }

    private func persistSnapshot(_ snapshot: FavoriteRemoteSyncSnapshot) async {
        // Unstructured task: the terminal snapshot of an interrupted run is
        // written from the cancelled sync task, and GRDB's async accesses
        // honor Task cancellation — the write must not inherit it.
        let runStore = runStore
        do {
            try await Task {
                try await runStore.save(snapshot)
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Background task

    @discardableResult
    private func beginBackgroundTask(runID: String) -> Bool {
#if canImport(UIKit)
        guard backgroundTaskID == .invalid else { return true }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "FavoriteRemoteSync") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.interruptionReasonBox.set(.backgroundExpired)
                self.syncTask?.cancel()
                self.endBackgroundTask()
            }
        }
        return backgroundTaskID != .invalid
#else
        return true
#endif
    }

    private func endBackgroundTask() {
#if canImport(UIKit)
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
#endif
    }

    // MARK: - Thread probing

    private static func probeResult(
        forThreadID threadID: String,
        title: String?,
        resolver: YamiboThreadRouteResolver,
        coverRepository: ForumThreadReaderRepository
    ) async throws -> FavoriteThreadProbeResult {
        let url = YamiboRoute.threadByID(tid: threadID, page: 1, authorID: nil, reverse: false).url
        switch try await resolver.resolve(YamiboThreadRouteRequest(threadURL: url, title: title)) {
        case let .novel(payload):
            let metadata = await threadMetadata(
                thread: ThreadIdentity(tid: payload.thread.tid),
                title: payload.title,
                repository: coverRepository
            )
            return FavoriteThreadProbeResult(
                target: .novelThread(threadID: payload.thread.tid),
                title: payload.title,
                sourceGroup: metadata.sourceGroup,
                coverURL: metadata.coverURL,
                contentUpdatedAt: metadata.contentUpdatedAt,
                authorID: payload.authorID
            )
        case let .manga(payload):
            let cleanBookName = MangaTitleCleaner.cleanBookName(payload.title)
            let mangaID = payload.thread.tid
            return FavoriteThreadProbeResult(
                target: FavoriteContentTarget(mangaID: "thread:\(mangaID)", mangaCleanBookName: cleanBookName),
                title: cleanBookName,
                sourceGroup: .mangaTitle(mangaID: "thread:\(mangaID)", cleanBookName: cleanBookName)
            )
        case let .thread(payload):
            let metadata = await threadMetadata(
                thread: payload.thread,
                title: payload.title,
                repository: coverRepository
            )
            return FavoriteThreadProbeResult(
                target: .normalThread(threadID: payload.thread.tid),
                title: payload.title,
                sourceGroup: metadata.sourceGroup,
                coverURL: metadata.coverURL,
                contentUpdatedAt: metadata.contentUpdatedAt
            )
        case let .webFallback(url):
            let canonicalURL = YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url) ?? url
            guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: canonicalURL) else {
                throw YamiboError.missingFavoriteThreadID
            }
            // Route the fallback through the routing payload so a missing or
            // blank title gets the same default as resolved `.thread` routes.
            let payload = YamiboThreadRoutePayload(
                thread: ThreadIdentity(tid: threadID),
                title: title ?? "",
                canonicalURL: canonicalURL,
                requestedURL: url
            )
            let metadata = await threadMetadata(
                thread: payload.thread,
                title: payload.title,
                repository: coverRepository
            )
            return FavoriteThreadProbeResult(
                target: .normalThread(threadID: threadID),
                title: payload.title,
                sourceGroup: metadata.sourceGroup,
                coverURL: metadata.coverURL,
                contentUpdatedAt: metadata.contentUpdatedAt
            )
        }
    }

    private static func threadMetadata(
        thread: ThreadIdentity,
        title: String,
        repository: ForumThreadReaderRepository
    ) async -> (coverURL: URL?, sourceGroup: FavoriteSourceGroup, contentUpdatedAt: Date?) {
        let cachedFirstPage = await repository.cachedThreadPage(thread: thread, title: title, authorID: nil, page: 1)
        let firstPage: ForumThreadPage?
        if let cachedFirstPage {
            firstPage = cachedFirstPage
        } else {
            firstPage = try? await repository.fetchThreadPage(thread: thread, title: title, authorID: nil, page: 1)
        }
        let sourceGroup = sourceGroup(from: firstPage)
        let contentUpdatedAt = contentUpdatedAt(from: firstPage)
        let coverURL = await ThreadCoverResolver().resolve(
            thread: thread,
            title: title,
            repository: repository
        )
        return (coverURL, sourceGroup, contentUpdatedAt)
    }

    private static func contentUpdatedAt(from page: ForumThreadPage?) -> Date? {
        guard let firstPost = page?.posts.first else { return nil }
        return FavoriteContentUpdateDateResolver.date(
            lastEditedText: firstPost.lastEditedText,
            postedAtText: firstPost.postedAtText
        )
    }

    private static func sourceGroup(from page: ForumThreadPage?) -> FavoriteSourceGroup {
        guard let page else { return .unknown }
        let fid = page.forumID ?? page.thread.fid
        guard let fid, !fid.isEmpty else { return .unknown }
        return .forumBoard(id: fid, label: page.forumName ?? fid)
    }
}

/// Caches the Yamibo formHash for the duration of one sync run so bulk
/// uploads do not re-fetch the profile page per item.
private actor FavoriteSyncFormHashBox {
    private var cached: String?

    func formHash(repository: FavoriteRepository) async throws -> String {
        if let cached { return cached }
        let value = try await repository.currentFormHash()
        cached = value
        return value
    }
}

/// Thread-safe slot for the reason an in-flight run is being cancelled, read
/// by the engine when it observes the cancellation.
private final class FavoriteSyncInterruptionReasonBox: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: FavoriteRemoteSyncWarning?

    func set(_ new: FavoriteRemoteSyncWarning?) {
        lock.lock()
        reason = new
        lock.unlock()
    }

    func take() -> FavoriteRemoteSyncWarning? {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }
}
