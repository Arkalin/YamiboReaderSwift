import Foundation
import UIKit
import YamiboReaderCore

/// State machine for one Yamibo remote favorite sync run: fetches the remote
/// favorite list, imports it into the local library document, and tracks
/// progress in a persisted `FavoriteRemoteSyncSnapshot`.
///
/// Library changes are written through the shared `FavoriteLibraryStore`,
/// whose change notification lets `FavoriteLibraryOrganizer` refresh itself;
/// this session never touches the organizer directly.
@MainActor
final class FavoriteRemoteSyncSession: ObservableObject {
    @Published private(set) var snapshot: FavoriteRemoteSyncSnapshot?
    @Published var errorMessage: String?

    private let libraryStore: FavoriteLibraryStore
    private let settingsStore: SettingsStore
    private let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    private let makeForumThreadReaderRepository: @Sendable () async -> ForumThreadReaderRepository
    private let makeThreadRouteResolver: @Sendable () async -> YamiboThreadRouteResolver
    private let executor: ((String, String) async throws -> YamiboFavoriteSyncReport)?

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
        settingsStore: SettingsStore,
        makeFavoriteRepository: @escaping @Sendable () async -> FavoriteRepository,
        makeForumThreadReaderRepository: @escaping @Sendable () async -> ForumThreadReaderRepository,
        makeThreadRouteResolver: @escaping @Sendable () async -> YamiboThreadRouteResolver,
        executor: ((String, String) async throws -> YamiboFavoriteSyncReport)? = nil
    ) {
        self.libraryStore = libraryStore
        self.settingsStore = settingsStore
        self.makeFavoriteRepository = makeFavoriteRepository
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.makeThreadRouteResolver = makeThreadRouteResolver
        self.executor = executor
    }

    deinit {
        syncTask?.cancel()
    }

    /// Restores the persisted snapshot; a snapshot still marked running whose
    /// task no longer exists is downgraded to interrupted.
    func load() async {
        let settings = await settingsStore.load()
        snapshot = await interruptedSnapshotIfNeeded(settings.favorites.remoteSyncSnapshot)
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
        let startedSnapshot = FavoriteRemoteSyncSnapshot(
            status: .running,
            targetCategoryID: targetCategoryID,
            targetCategoryName: categoryName,
            phase: L10n.string("favorites.sync.phase.queued"),
            startedAt: now,
            updatedAt: now,
            logMessages: [L10n.string("favorites.sync.log.started", categoryName)]
        )
        snapshot = startedSnapshot
        await persistSnapshot(startedSnapshot)

        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            await self?.run(runID: startedSnapshot.runID, targetCategoryID: targetCategoryID)
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
        guard let runID = snapshot?.runID, snapshot?.status == .running else { return }
        syncTask?.cancel()
        Self.activeRunCancelHandlers[runID]?()
        await updateSnapshot { snapshot in
            snapshot.status = .interrupted
            snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
            snapshot.finishedAt = .now
            snapshot.warningMessages.append(L10n.string("favorites.sync.warning.interrupted_by_user"))
            snapshot.logMessages.append(L10n.string("favorites.sync.log.interrupted"))
        }
        endBackgroundTask()
    }

    func hideCard() async {
        guard snapshot != nil else { return }
        await updateSnapshot { snapshot in
            snapshot.isHiddenFromFavoritePage = true
        }
    }

    // MARK: - Run

    private func run(runID: String, targetCategoryID: String) async {
        beginBackgroundTask(runID: runID)
        defer {
            endBackgroundTask()
            Self.activeRunCancelHandlers[runID] = nil
        }

        do {
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.phase = L10n.string("favorites.sync.phase.fetching")
                snapshot.logMessages.append(L10n.string("favorites.sync.log.fetching"))
            }
            if let executor {
                let report = try await executor(runID, targetCategoryID)
                try Task.checkCancellation()
                await finish(runID: runID, report: report)
                return
            }
            let repository = await makeFavoriteRepository()
            let remoteFavorites = try await repository.fetchFavorites()
            try Task.checkCancellation()
            var updatedDocument = await libraryStore.load()
            let entries = remoteFavorites.enumerated().map { index, favorite in
                YamiboRemoteFavoriteEntry(
                    remoteFavoriteID: favorite.remoteFavoriteID ?? favorite.id,
                    threadID: favorite.threadID,
                    title: favorite.title,
                    remoteOrder: index
                )
            }
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.phase = L10n.string("favorites.sync.phase.importing")
                snapshot.totalRemoteCount = entries.count
                snapshot.scannedCount = entries.count
                snapshot.logMessages.append(L10n.string("favorites.sync.log.fetched", entries.count))
            }
            let resolver = await makeThreadRouteResolver()
            let coverRepository = await makeForumThreadReaderRepository()
            let report = await updatedDocument.syncYamiboRemoteFavorites(
                into: targetCategoryID,
                remoteEntries: entries,
                date: .now,
                probe: { threadID in
                    let title = remoteFavorites.first { $0.threadID == threadID }?.title
                    return try await Self.probeResult(
                        forThreadID: threadID,
                        title: title,
                        resolver: resolver,
                        coverRepository: coverRepository
                    )
                }
            )
            try Task.checkCancellation()
            try await libraryStore.save(updatedDocument)
            errorMessage = nil
            await finish(runID: runID, report: report)
        } catch {
            if error.isTaskCancellation {
                await updateSnapshot(runID: runID) { snapshot in
                    snapshot.status = .interrupted
                    snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
                    snapshot.finishedAt = .now
                    snapshot.warningMessages.append(L10n.string("favorites.sync.warning.interrupted"))
                    snapshot.logMessages.append(L10n.string("favorites.sync.log.interrupted"))
                }
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.status = .failed
                snapshot.phase = L10n.string("favorites.sync.phase.failed")
                snapshot.finishedAt = .now
                snapshot.errorMessages.append(message)
                snapshot.logMessages.append(L10n.string("favorites.sync.log.failed"))
            }
        }
    }

    private func finish(runID: String, report: YamiboFavoriteSyncReport) async {
        await updateSnapshot(runID: runID) { snapshot in
            snapshot.status = .completed
            snapshot.phase = L10n.string("favorites.sync.phase.completed")
            snapshot.finishedAt = .now
            snapshot.importedCount = report.importedTargetIDs.count
            snapshot.failedCount = report.failedRemoteFavoriteIDs.count
            snapshot.markedMissingCount = report.markedMissingTargetIDs.count
            snapshot.uploadTargetCount = report.uploadTargetIDs.count
            snapshot.logMessages.append(L10n.string("favorites.sync.log.completed", report.importedTargetIDs.count))
            if !report.failedRemoteFavoriteIDs.isEmpty {
                snapshot.warningMessages.append(L10n.string("favorites.sync.warning.failed_items", report.failedRemoteFavoriteIDs.count))
            }
            if !report.uploadTargetIDs.isEmpty {
                snapshot.warningMessages.append(L10n.string("favorites.sync.warning.upload_pending", report.uploadTargetIDs.count))
            }
        }
    }

    // MARK: - Snapshot state

    private func interruptedSnapshotIfNeeded(_ snapshot: FavoriteRemoteSyncSnapshot?) async -> FavoriteRemoteSyncSnapshot? {
        guard var snapshot else { return nil }
        guard snapshot.status == .running else { return snapshot }
        guard !Self.isRunActive(snapshot.runID) else { return snapshot }
        snapshot.status = .interrupted
        snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
        snapshot.finishedAt = snapshot.finishedAt ?? .now
        snapshot.updatedAt = .now
        snapshot.warningMessages.append(L10n.string("favorites.sync.warning.task_lost"))
        snapshot.logMessages.append(L10n.string("favorites.sync.log.task_lost"))
        await persistSnapshot(snapshot)
        return snapshot
    }

    private func updateSnapshot(
        runID: String? = nil,
        mutate: (inout FavoriteRemoteSyncSnapshot) -> Void
    ) async {
        guard var snapshot else { return }
        if let runID, snapshot.runID != runID { return }
        mutate(&snapshot)
        snapshot.updatedAt = .now
        self.snapshot = snapshot
        await persistSnapshot(snapshot)
    }

    private func persistSnapshot(_ snapshot: FavoriteRemoteSyncSnapshot) async {
        var settings = await settingsStore.load()
        settings.favorites.remoteSyncSnapshot = snapshot
        do {
            try await settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Background task

    private func beginBackgroundTask(runID: String) {
#if canImport(UIKit)
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "FavoriteRemoteSync") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncTask?.cancel()
                await self.updateSnapshot(runID: runID) { snapshot in
                    snapshot.status = .interrupted
                    snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
                    snapshot.finishedAt = .now
                    snapshot.warningMessages.append(L10n.string("favorites.sync.warning.background_expired"))
                    snapshot.logMessages.append(L10n.string("favorites.sync.log.interrupted"))
                }
                self.endBackgroundTask()
            }
        }
        if backgroundTaskID == .invalid {
            Task { @MainActor in
                await updateSnapshot(runID: runID) { snapshot in
                    snapshot.warningMessages.append(L10n.string("favorites.sync.warning.background_unavailable"))
                }
            }
        }
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
            let resolvedTitle = title ?? L10n.string("forum.default_title")
            let canonicalURL = YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url) ?? url
            guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: canonicalURL) else {
                throw YamiboError.missingFavoriteThreadID
            }
            let metadata = await threadMetadata(
                thread: ThreadIdentity(tid: threadID),
                title: resolvedTitle,
                repository: coverRepository
            )
            return FavoriteThreadProbeResult(
                target: .normalThread(threadID: threadID),
                title: resolvedTitle,
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

/// Shared cancellation detection for favorite background sessions.
extension Error {
    var isTaskCancellation: Bool {
        if self is CancellationError {
            return true
        }
        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
