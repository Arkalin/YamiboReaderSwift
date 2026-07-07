import Foundation
import YamiboReaderCore

/// State machine for favorite update detection: walks tracked threads,
/// compares fingerprints against the stored baseline, and records update
/// events plus per-forum and per-category filters.
@MainActor
final class FavoriteUpdateMonitor: ObservableObject {
    @Published private(set) var snapshot: FavoriteUpdateRunSnapshot?
    @Published private(set) var events: [FavoriteUpdateEvent] = []
    @Published private(set) var fidFilters: [FavoriteUpdateFidFilter] = []
    @Published private(set) var categoryFilters: [FavoriteUpdateCategoryFilter] = []
    @Published var errorMessage: String?

    private let updateStore: FavoriteUpdateStore
    private let libraryStore: FavoriteLibraryStore
    private let makeForumThreadReaderRepository: @Sendable () async -> ForumThreadReaderRepository
    private let settingsStore: SettingsStore?
    private let pageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)?

    private var checkTask: Task<Void, Never>?

    init(
        updateStore: FavoriteUpdateStore,
        libraryStore: FavoriteLibraryStore,
        makeForumThreadReaderRepository: @escaping @Sendable () async -> ForumThreadReaderRepository,
        settingsStore: SettingsStore? = nil,
        pageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)? = nil
    ) {
        self.updateStore = updateStore
        self.libraryStore = libraryStore
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.settingsStore = settingsStore
        self.pageFetcher = pageFetcher
    }

    deinit {
        checkTask?.cancel()
    }

    /// Reloads the persisted run, events, and filters. A run still marked
    /// running whose task no longer exists is downgraded to interrupted.
    func load() async {
        var latest = await updateStore.latestRun()
        if var loaded = latest, loaded.status == .running, checkTask == nil {
            loaded.status = .interrupted
            loaded.phase = .interrupted
            loaded.finishedAt = loaded.finishedAt ?? .now
            loaded.updatedAt = .now
            loaded.progress = nil
            try? await updateStore.saveRun(loaded)
            latest = loaded
        }
        snapshot = latest
        await reloadEventState()
    }

    /// Refreshes events and filters from the store. Kept separate from the
    /// snapshot so a run can publish fresh event state before its terminal
    /// status becomes observable.
    private func reloadEventState() async {
        let state = await updateStore.loadState()
        events = state.events
            .filter { $0.dismissedAt == nil }
            .sorted { lhs, rhs in
                if lhs.detectedAt != rhs.detectedAt { return lhs.detectedAt > rhs.detectedAt }
                return lhs.id > rhs.id
            }
        fidFilters = state.fidFilters.sorted { lhs, rhs in
            if lhs.forumName != rhs.forumName { return lhs.forumName < rhs.forumName }
            return lhs.fid < rhs.fid
        }
        categoryFilters = state.categoryFilters.sorted { lhs, rhs in
            if lhs.categoryName != rhs.categoryName { return lhs.categoryName < rhs.categoryName }
            return lhs.categoryID < rhs.categoryID
        }
    }

    @discardableResult
    func startCheck() async -> String? {
        if snapshot?.status == .running {
            return snapshot?.runID
        }
        let now = Date()
        let startedSnapshot = FavoriteUpdateRunSnapshot(
            status: .running,
            phase: .preparing,
            startedAt: now,
            updatedAt: now
        )
        snapshot = startedSnapshot
        do {
            try await updateStore.saveRun(startedSnapshot)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        checkTask?.cancel()
        checkTask = Task { @MainActor [weak self] in
            await self?.runCheck(runID: startedSnapshot.runID)
        }
        return startedSnapshot.runID
    }

    func interrupt() async {
        guard snapshot?.status == .running else { return }
        checkTask?.cancel()
        await updateSnapshot { snapshot in
            snapshot.status = .interrupted
            snapshot.phase = .interrupted
            snapshot.finishedAt = .now
            snapshot.progress = nil
        }
    }

    /// Waits for an in-flight check to finish (background refresh completion).
    func waitForCompletion() async {
        await checkTask?.value
    }

    /// Configured automatic check interval, or nil without a settings store.
    func configuredInterval() async -> FavoriteUpdateCheckInterval? {
        guard let settingsStore else { return nil }
        return await settingsStore.load().favorites.updateCheckInterval
    }

    func setConfiguredInterval(_ interval: FavoriteUpdateCheckInterval) async {
        guard let settingsStore else { return }
        var settings = await settingsStore.load()
        settings.favorites.updateCheckInterval = interval
        try? await settingsStore.save(settings)
    }

    /// Whether recent events keep arriving; drives the smart interval.
    var hasRecentEvents: Bool {
        events.contains { $0.detectedAt > Date.now.addingTimeInterval(-7 * 24 * 3600) }
    }

    /// Starts a check when the configured interval has elapsed since the last
    /// completed run — the foreground catch-up half of automatic checking
    /// (BGAppRefreshTask timing is only best-effort).
    @discardableResult
    func startCheckIfDue() async -> Bool {
        guard let interval = await configuredInterval(),
              let delay = interval.nextDelay(hasRecentEvents: hasRecentEvents) else {
            return false
        }
        guard snapshot?.status != .running else { return false }
        if let last = snapshot, last.status == .completed, let finishedAt = last.finishedAt,
           Date.now.timeIntervalSince(finishedAt) < delay {
            return false
        }
        return await startCheck() != nil
    }

    // MARK: - Events and filters

    func markEventRead(_ eventID: String) async {
        do {
            try await updateStore.markEventRead(eventID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissEvent(_ eventID: String) async {
        do {
            try await updateStore.dismissEvent(eventID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissAllEvents() async {
        do {
            try await updateStore.dismissAllEvents()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFidFilter(_ fid: String, enabled: Bool) async {
        do {
            try await updateStore.setFidEnabled(fid, enabled: enabled)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCategoryFilter(_ categoryID: String, enabled: Bool) async {
        do {
            try await updateStore.setCategoryEnabled(categoryID, enabled: enabled)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Check run

    private func runCheck(runID: String) async {
        do {
            let document = await libraryStore.load()
            let candidates = Self.candidates(in: document)
            try await refreshFilters(candidates: candidates, document: document)
            let scopedCandidates = await scopedCandidates(candidates)
            try await replaceTrackedTargetsIfNeeded(candidates)
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.phase = .checking
                snapshot.totalCount = scopedCandidates.count
                snapshot.progress = .loadedTargets(count: scopedCandidates.count)
            }

            var detectedCount = 0
            for (index, item) in scopedCandidates.enumerated() {
                try Task.checkCancellation()
                await updateSnapshot(runID: runID) { snapshot in
                    snapshot.progress = .checking(
                        index: index + 1,
                        total: scopedCandidates.count,
                        title: item.resolvedDisplayTitle
                    )
                }
                let result = await checkUpdate(for: item)
                switch result {
                case let .checked(detected):
                    detectedCount += detected
                    await updateSnapshot(runID: runID) { snapshot in
                        snapshot.completedCount += 1
                        snapshot.detectedCount = detectedCount
                    }
                case .skipped:
                    await updateSnapshot(runID: runID) { snapshot in
                        snapshot.skippedCount += 1
                    }
                case let .failed(message):
                    await updateSnapshot(runID: runID) { snapshot in
                        snapshot.failedCount += 1
                        snapshot.warningMessage = [snapshot.warningMessage, message].compactMap { $0 }.joined(separator: "\n")
                    }
                }
            }

            await reloadEventState()
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.status = .completed
                snapshot.phase = .completed
                snapshot.finishedAt = .now
                snapshot.progress = nil
            }
        } catch {
            if error.isTaskCancellation {
                await reloadEventState()
                await updateSnapshot(runID: runID) { snapshot in
                    snapshot.status = .interrupted
                    snapshot.phase = .interrupted
                    snapshot.finishedAt = .now
                    snapshot.progress = nil
                }
                return
            }
            await reloadEventState()
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.status = .failed
                snapshot.phase = .failed
                snapshot.finishedAt = .now
                snapshot.progress = nil
                snapshot.errorMessage = error.localizedDescription
            }
        }
    }

    private func updateSnapshot(
        runID: String? = nil,
        mutate: (inout FavoriteUpdateRunSnapshot) -> Void
    ) async {
        guard var snapshot else { return }
        if let runID, snapshot.runID != runID { return }
        mutate(&snapshot)
        snapshot.updatedAt = .now
        self.snapshot = snapshot
        do {
            try await updateStore.saveRun(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Candidates

    private static func candidates(in document: FavoriteLibraryDocument) -> [FavoriteItem] {
        document.items.filter { item in
            item.target.threadID != nil && (item.target.kind == .normalThread || item.target.kind == .novelThread)
        }
    }

    private func refreshFilters(candidates: [FavoriteItem], document: FavoriteLibraryDocument) async throws {
        let now = Date()
        let categoryNames = Dictionary(uniqueKeysWithValues: document.categories.map { ($0.id, $0.displayName) })
        var categoryCounts: [String: Int] = [:]
        var fidCounts: [FavoriteSourceGroup: Int] = [:]
        for item in candidates {
            for categoryID in Set(item.locations.compactMap(\.categoryID)) {
                categoryCounts[categoryID, default: 0] += 1
            }
            fidCounts[item.sourceGroup, default: 0] += 1
        }
        let categoryFilters = categoryCounts.map { categoryID, count in
            FavoriteUpdateCategoryFilter(
                categoryID: categoryID,
                categoryName: categoryNames[categoryID] ?? categoryID,
                itemCount: count,
                updatedAt: now
            )
        }
        let fidFilters = fidCounts.compactMap { sourceGroup, count -> FavoriteUpdateFidFilter? in
            guard case let .forumBoard(id, label) = sourceGroup else { return nil }
            return FavoriteUpdateFidFilter(fid: id, forumName: label, itemCount: count, updatedAt: now)
        }
        try await updateStore.replaceFilters(
            fidFilters: fidFilters.sorted { $0.fid < $1.fid },
            categoryFilters: categoryFilters.sorted { $0.categoryID < $1.categoryID }
        )
    }

    private func scopedCandidates(_ candidates: [FavoriteItem]) async -> [FavoriteItem] {
        let state = await updateStore.loadState()
        let enabledFids = Set(state.fidFilters.filter(\.enabled).map(\.fid))
        let disabledFidsExist = state.fidFilters.contains { !$0.enabled }
        let enabledCategories = Set(state.categoryFilters.filter(\.enabled).map(\.categoryID))
        let disabledCategoriesExist = state.categoryFilters.contains { !$0.enabled }
        return candidates.filter { item in
            let fidMatches: Bool
            if disabledFidsExist {
                if case let .forumBoard(id, _) = item.sourceGroup {
                    fidMatches = enabledFids.contains(id)
                } else {
                    fidMatches = false
                }
            } else {
                fidMatches = true
            }
            let categoryMatches = !disabledCategoriesExist || !Set(item.locations.compactMap(\.categoryID)).isDisjoint(with: enabledCategories)
            return fidMatches && categoryMatches
        }
    }

    private func replaceTrackedTargetsIfNeeded(_ candidates: [FavoriteItem]) async throws {
        let state = await updateStore.loadState()
        let existingByID = Dictionary(uniqueKeysWithValues: state.trackedTargets.map { ($0.id, $0) })
        let targets = candidates.map { item -> FavoriteUpdateTrackedTarget in
            var existing = existingByID[item.target.id] ?? FavoriteUpdateTrackedTarget(
                target: item.target,
                title: item.resolvedDisplayTitle,
                mode: item.target.kind == .novelThread ? .novelThread : .normalThread
            )
            existing.title = item.resolvedDisplayTitle
            existing.mode = item.target.kind == .novelThread ? .novelThread : .normalThread
            existing.categoryIDs = Set(item.locations.compactMap(\.categoryID))
            if case let .forumBoard(id, label) = item.sourceGroup {
                existing.fid = id
                existing.forumName = label
            }
            return existing
        }
        try await updateStore.replaceTrackedTargets(targets)
    }

    // MARK: - Single item check

    private enum CheckResult {
        case checked(detected: Int)
        case skipped
        case failed(String)
    }

    private func checkUpdate(for item: FavoriteItem) async -> CheckResult {
        guard let page = await threadPage(for: item) else { return .skipped }
        let fingerprint = FavoriteUpdateFingerprint(page: page)
        let state = await updateStore.loadState()
        var target = state.trackedTargets.first { $0.target == item.target } ?? FavoriteUpdateTrackedTarget(
            target: item.target,
            title: item.resolvedDisplayTitle,
            mode: item.target.kind == .novelThread ? .novelThread : .normalThread
        )
        let previous = FavoriteUpdateFingerprint(target: target)
        target.knownLatestPostID = fingerprint.latestPostID
        target.knownReplyCount = fingerprint.replyCount
        target.knownPageCount = fingerprint.pageCount
        target.baselineReady = true
        target.lastCheckedAt = .now
        target.lastError = nil
        target.consecutiveFailures = 0
        if let forumID = page.forumID ?? page.thread.fid {
            target.fid = forumID
        }
        if let forumName = page.forumName {
            target.forumName = forumName
        }

        do {
            try await updateStore.upsertTrackedTarget(target)
            guard previous.isReady, fingerprint.isNewer(than: previous) else {
                return .checked(detected: 0)
            }
            let summary = FavoriteUpdateFingerprint.summary(from: previous, to: fingerprint)
            let event = FavoriteUpdateEvent(
                target: item.target,
                title: item.resolvedDisplayTitle,
                mode: item.target.kind == .novelThread ? .novelThread : .normalThread,
                fid: target.fid,
                forumName: target.forumName,
                summary: summary,
                detailIDs: fingerprint.latestPostID.map { [$0] } ?? [],
                detectedAt: .now,
                ambiguous: fingerprint.latestPostID == nil
            )
            try await updateStore.insertEvent(event)
            return .checked(detected: 1)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func threadPage(for item: FavoriteItem) async -> ForumThreadPage? {
        do {
            if let pageFetcher {
                return try await pageFetcher(item)
            }
            guard let tid = item.target.threadID else {
                return nil
            }
            let repository = await makeForumThreadReaderRepository()
            let fid: String? = if case let .forumBoard(id, _) = item.sourceGroup { id } else { nil }
            let thread = ThreadIdentity(tid: tid, fid: fid)
            let context = ThreadNovelLaunchContext(thread: thread, title: item.resolvedDisplayTitle)
            return try await repository.fetchThreadPage(context: context, page: 1)
        } catch {
            return nil
        }
    }
}

/// Compact comparison key for detecting thread updates between check runs.
private struct FavoriteUpdateFingerprint: Sendable {
    var latestPostID: String?
    var replyCount: Int?
    var pageCount: Int?
    var isReady: Bool

    init(page: ForumThreadPage) {
        latestPostID = page.posts.map(\.postID).last
        replyCount = page.totalReplies
        pageCount = page.pageNavigation?.totalPages
        isReady = latestPostID != nil || replyCount != nil || pageCount != nil
    }

    init(target: FavoriteUpdateTrackedTarget) {
        latestPostID = target.knownLatestPostID
        replyCount = target.knownReplyCount
        pageCount = target.knownPageCount
        isReady = target.baselineReady
    }

    func isNewer(than previous: FavoriteUpdateFingerprint) -> Bool {
        if let replyCount, let previousReplyCount = previous.replyCount, replyCount > previousReplyCount {
            return true
        }
        if let pageCount, let previousPageCount = previous.pageCount, pageCount > previousPageCount {
            return true
        }
        if let latestPostID, latestPostID != previous.latestPostID {
            return true
        }
        return false
    }

    static func summary(from previous: FavoriteUpdateFingerprint, to current: FavoriteUpdateFingerprint) -> FavoriteUpdateSummary {
        if let replyCount = current.replyCount, let previousReplyCount = previous.replyCount, replyCount > previousReplyCount {
            return .newReplies(count: replyCount - previousReplyCount)
        }
        if let pageCount = current.pageCount, let previousPageCount = previous.pageCount, pageCount > previousPageCount {
            return .newPages(count: pageCount - previousPageCount)
        }
        return .changed
    }
}
