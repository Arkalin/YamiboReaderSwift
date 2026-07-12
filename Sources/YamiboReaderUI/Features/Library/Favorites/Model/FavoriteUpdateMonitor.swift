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
    /// The authoritative per-target category scope, keyed by
    /// `FavoriteUpdateTargetKey`. UI category-filter matching for a
    /// `.mangaDirectory` event must read this rather than guessing from
    /// `FavoriteItem.target.id` equality (that lookup is `.favorite`-only by
    /// construction — a directory event's target id never matches one).
    @Published private(set) var trackedTargets: [FavoriteUpdateTrackedTarget] = []
    @Published var errorMessage: String?

    private let updateStore: FavoriteUpdateStore
    private let libraryStore: FavoriteLibraryStore
    private let makeForumThreadReaderRepository: @Sendable () async -> ForumThreadReaderRepository
    private let settingsStore: SettingsStore?
    private let notifier: (any FavoriteUpdateNotifying)?
    private let pageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)?
    /// Batched tid -> directory resolution for the smart-manga check lane.
    /// `nil` (the default) makes that lane a no-op, same as every other
    /// optional dependency here — production wiring supplies the real
    /// `MangaDirectoryStore` in a later phase; this phase only wires
    /// dependency-injection plumbing plus internal candidate/check logic.
    private let mangaDirectoryStore: (any MangaDirectoryPersisting)?
    /// Builds a fresh `MangaDirectoryWorkflow` scoped to one directory
    /// group's board (`searchForumID`), mirroring `makeForumThreadReaderRepository`'s
    /// "construct fresh per call so session state stays current" shape. `nil`
    /// makes the smart-manga check lane a no-op even if `mangaDirectoryStore`
    /// is set (seeding still runs — only network refresh needs a workflow).
    private let makeMangaDirectoryWorkflow: (@Sendable (_ searchForumID: String) async -> MangaDirectoryWorkflow)?

    private var checkTask: Task<Void, Never>?
    private var storeUpdatesTask: Task<Void, Never>?

    private static var activeRunIDs: Set<String> = []

    private static func isRunActive(_ runID: String) -> Bool {
        activeRunIDs.contains(runID)
    }

    init(
        updateStore: FavoriteUpdateStore,
        libraryStore: FavoriteLibraryStore,
        makeForumThreadReaderRepository: @escaping @Sendable () async -> ForumThreadReaderRepository,
        settingsStore: SettingsStore? = nil,
        notifier: (any FavoriteUpdateNotifying)? = nil,
        pageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)? = nil,
        mangaDirectoryStore: (any MangaDirectoryPersisting)? = nil,
        makeMangaDirectoryWorkflow: (@Sendable (_ searchForumID: String) async -> MangaDirectoryWorkflow)? = nil
    ) {
        self.updateStore = updateStore
        self.libraryStore = libraryStore
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.settingsStore = settingsStore
        self.notifier = notifier
        self.pageFetcher = pageFetcher
        self.mangaDirectoryStore = mangaDirectoryStore
        self.makeMangaDirectoryWorkflow = makeMangaDirectoryWorkflow
        storeUpdatesTask = Task { @MainActor [weak self, store = updateStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteUpdateStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteUpdateStore.changeIDUserInfoKey] as? String,
                      changeID == store.changeID else {
                    continue
                }
                // Skip while this instance is actively driving its own check
                // run — its explicit updateSnapshot/reloadEventState calls
                // already keep it current, so reloading here would just be
                // redundant churn. Once idle, any store change (including
                // one from a different monitor instance, e.g. a background
                // refresh task) must be picked up so the UI never sits on
                // stale background-detected results.
                guard self.snapshot?.status != .running else { continue }
                await self.reloadFromExternalChange()
            }
        }
    }

    deinit {
        checkTask?.cancel()
        storeUpdatesTask?.cancel()
    }

    /// Reloads the persisted run, events, and filters. A run still marked
    /// running whose task no longer exists is downgraded to interrupted.
    func load() async {
        snapshot = await fetchLatestRunDowngradingIfOrphaned()
        await reloadEventState()
    }

    /// Applies a store change observed via notification. The notification
    /// consumer can fall arbitrarily far behind under scheduler contention
    /// (it drains a backlog that includes this very instance's own writes
    /// from the run that just finished), so unlike `load()` this
    /// re-validates immediately before publishing that no new run has
    /// started on this instance while the store read was in flight —
    /// applying a stale read at that point would regress the visible
    /// snapshot back to the old run's runID and silently break the new
    /// run's own updateSnapshot(runID:) calls, which compare against
    /// self.snapshot.runID and no-op on a mismatch.
    private func reloadFromExternalChange() async {
        let latest = await fetchLatestRunDowngradingIfOrphaned()
        guard snapshot?.status != .running else { return }
        snapshot = latest
        await reloadEventState()
    }

    private func fetchLatestRunDowngradingIfOrphaned() async -> FavoriteUpdateRunSnapshot? {
        var latest = await updateStore.latestRun()
        if var loaded = latest, loaded.status == .running, !Self.isRunActive(loaded.runID) {
            loaded.status = .interrupted
            loaded.phase = .interrupted
            loaded.finishedAt = loaded.finishedAt ?? .now
            loaded.updatedAt = .now
            loaded.progress = nil
            do {
                try await updateStore.saveRun(loaded)
            } catch {
                YamiboLog.persistence.error("Failed to persist interrupted-run downgrade for favorite update run \(loaded.runID): \(error.localizedDescription)")
            }
            latest = loaded
        }
        return latest
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
        trackedTargets = state.trackedTargets
    }

    /// - Parameter nonTagMangaDirectoryCheckCap: Ceiling on how many
    ///   NON-tag-strategy smart-manga directory groups (the ones whose
    ///   refresh always risks the forum's search flood-control) this run
    ///   will attempt a network refresh for; tag-strategy groups are
    ///   unbounded (cheap, no search cooldown in the common case). Callers
    ///   should pass a small number for background-triggered runs and a
    ///   larger one for foreground/manual runs — this type has no opinion on
    ///   which, it only enforces whatever cap it's given.
    @discardableResult
    func startCheck(nonTagMangaDirectoryCheckCap: Int = 1) async -> String? {
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
            YamiboLog.persistence.error("Failed to persist initial running snapshot for favorite update run \(startedSnapshot.runID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return nil
        }
        checkTask?.cancel()
        checkTask = Task { @MainActor [weak self] in
            await self?.runCheck(runID: startedSnapshot.runID, nonTagMangaDirectoryCheckCap: nonTagMangaDirectoryCheckCap)
        }
        Self.activeRunIDs.insert(startedSnapshot.runID)
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
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.persistence.error("Failed to persist favorite update check interval: \(error.localizedDescription)")
        }
    }

    /// Configured smart-manga chapter check interval, or nil without a
    /// settings store — the UI-facing counterpart of `smartMangaInterval()`
    /// (which the check run itself reads).
    func configuredMangaInterval() async -> SmartMangaUpdateCheckInterval? {
        guard let settingsStore else { return nil }
        return await settingsStore.load().favorites.smartMangaUpdateCheckInterval
    }

    func setConfiguredMangaInterval(_ interval: SmartMangaUpdateCheckInterval) async {
        guard let settingsStore else { return }
        var settings = await settingsStore.load()
        settings.favorites.smartMangaUpdateCheckInterval = interval
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.persistence.error("Failed to persist smart-manga update check interval: \(error.localizedDescription)")
        }
    }

    /// Whether recent events keep arriving; drives the smart interval.
    var hasRecentEvents: Bool {
        events.contains { $0.detectedAt > Date.now.addingTimeInterval(-7 * 24 * 3600) }
    }

    /// Smart-manga-only counterpart of `hasRecentEvents`, driving
    /// `SmartMangaUpdateCheckInterval.smart`'s adaptive cadence
    /// independently of thread-check activity.
    private var hasRecentMangaDirectoryEvents: Bool {
        events.contains {
            $0.mode == .mangaDirectory && $0.detectedAt > Date.now.addingTimeInterval(-7 * 24 * 3600)
        }
    }

    // MARK: - Update notifications

    /// Whether detected updates are delivered as local notifications.
    func notificationsEnabled() async -> Bool {
        guard let settingsStore else { return false }
        return await settingsStore.load().favorites.updateNotificationsEnabled
    }

    /// Persists the notification toggle and returns the effective value.
    /// Enabling requests system authorization first, so the stored setting
    /// can only be true after a grant — a denied request leaves it off.
    @discardableResult
    func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
        guard let settingsStore, let notifier else { return false }
        var effective = enabled
        if enabled {
            switch await notifier.authorization() {
            case .granted:
                break
            case .notDetermined:
                effective = await notifier.requestAuthorization()
            case .denied:
                effective = false
            }
        }
        var settings = await settingsStore.load()
        settings.favorites.updateNotificationsEnabled = effective
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.persistence.error("Failed to persist favorite update notification toggle: \(error.localizedDescription)")
        }
        if !effective {
            let identifiers = events.map { FavoriteUpdateNotification.identifier(forTargetID: $0.target.id) }
            await notifier.removeDelivered(identifiers: identifiers)
            await notifier.setBadgeCount(0)
        }
        return effective
    }

    /// True when the user's toggle is on but the system permission has since
    /// been revoked — deliveries are silently skipped in that state.
    func notificationsBlockedBySystem() async -> Bool {
        guard let notifier, await notificationsEnabled() else { return false }
        return await notifier.authorization() == .denied
    }

    /// Delivers a local notification for a freshly inserted event. Sharing
    /// the event's target-keyed identifier means an accumulated re-detection
    /// replaces the favorite's previous notification instead of stacking.
    private func deliverNotificationIfEnabled(for event: FavoriteUpdateEvent) async {
        guard let notifier, await notificationsEnabled() else { return }
        guard await notifier.authorization() == .granted else { return }
        let unreadCount = await updateStore.loadState().events
            .filter { $0.dismissedAt == nil && $0.readAt == nil }
            .count
        await notifier.deliver(FavoriteUpdateNotification(event: event, badgeCount: unreadCount))
    }

    /// Removes the delivered notifications for events the user has handled
    /// in-app and re-syncs the icon badge to the remaining unread count.
    private func cleanUpNotifications(forTargetIDs targetIDs: [String]) async {
        guard let notifier else { return }
        if !targetIDs.isEmpty {
            await notifier.removeDelivered(identifiers: targetIDs.map(FavoriteUpdateNotification.identifier(forTargetID:)))
        }
        guard await notificationsEnabled() else { return }
        await notifier.setBadgeCount(events.filter { $0.readAt == nil }.count)
    }

    /// Starts a check when the configured interval has elapsed since the last
    /// completed run — the foreground catch-up half of automatic checking
    /// (BGAppRefreshTask timing is only best-effort).
    /// Gating stays keyed on the thread-check interval only (unchanged from
    /// before smart-manga checking existed): a whole run always attempts
    /// both lanes, but whether a run happens automatically at all is still
    /// decided by `favorites.updateCheckInterval`. `smartMangaUpdateCheckInterval`
    /// only decides which *individual directory groups* are due once a run
    /// is already underway (see `checkMangaDirectoryGroups`) — it does not
    /// independently trigger runs. This is a deliberate scope boundary, not
    /// an oversight: unifying the two into an OR-gate here would make
    /// `smartMangaUpdateCheckInterval`'s non-off default silently start
    /// automatic background activity for every user, including those who
    /// have never touched smart manga and still have the thread-check
    /// interval at its `.off` default. Flagged for product-decision
    /// confirmation before the next phase wires a background trigger.
    @discardableResult
    func startCheckIfDue(nonTagMangaDirectoryCheckCap: Int = 1) async -> Bool {
        guard let interval = await configuredInterval(),
              let delay = interval.nextDelay(hasRecentEvents: hasRecentEvents) else {
            return false
        }
        guard snapshot?.status != .running else { return false }
        // Throttle on elapsed time regardless of how the last run ended: a
        // failed or interrupted run (e.g. the background task's execution
        // budget expired mid-check) must not bypass the interval and trigger
        // a brand-new full check on every single foreground catch-up.
        if let last = snapshot, let finishedAt = last.finishedAt,
           Date.now.timeIntervalSince(finishedAt) < delay {
            return false
        }
        return await startCheck(nonTagMangaDirectoryCheckCap: nonTagMangaDirectoryCheckCap) != nil
    }

    // MARK: - Events and filters

    func markEventRead(_ eventID: String) async {
        let targetIDs = events.filter { $0.id == eventID }.map(\.target.id)
        do {
            try await updateStore.markEventRead(eventID)
            await load()
            await cleanUpNotifications(forTargetIDs: targetIDs)
        } catch {
            YamiboLog.persistence.error("Failed to mark favorite update event \(eventID) read: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func dismissEvent(_ eventID: String) async {
        let targetIDs = events.filter { $0.id == eventID }.map(\.target.id)
        do {
            try await updateStore.dismissEvent(eventID)
            await load()
            await cleanUpNotifications(forTargetIDs: targetIDs)
        } catch {
            YamiboLog.persistence.error("Failed to dismiss favorite update event \(eventID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func dismissAllEvents() async {
        let targetIDs = events.map(\.target.id)
        do {
            try await updateStore.dismissAllEvents()
            await load()
            await cleanUpNotifications(forTargetIDs: targetIDs)
        } catch {
            YamiboLog.persistence.error("Failed to dismiss all favorite update events: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func setFidFilter(_ fid: String, enabled: Bool) async {
        do {
            try await updateStore.setFidEnabled(fid, enabled: enabled)
            await load()
        } catch {
            YamiboLog.persistence.error("Failed to toggle favorite update forum filter \(fid): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func setCategoryFilter(_ categoryID: String, enabled: Bool) async {
        do {
            try await updateStore.setCategoryEnabled(categoryID, enabled: enabled)
            await load()
        } catch {
            YamiboLog.persistence.error("Failed to toggle favorite update category filter \(categoryID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Check run

    private func runCheck(runID: String, nonTagMangaDirectoryCheckCap: Int) async {
        defer { Self.activeRunIDs.remove(runID) }
        do {
            let document = try await libraryStore.load()
            let candidates = Self.candidates(in: document)
            try await refreshFilters(candidates: candidates, document: document)
            let scopedCandidates = await scopedCandidates(candidates)
            try await replaceTrackedTargetsIfNeeded(candidates)
            let mangaGroups = await mangaDirectoryGroups(in: document)
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

            try Task.checkCancellation()
            await checkMangaDirectoryGroups(
                mangaGroups,
                nonTagCheckCap: nonTagMangaDirectoryCheckCap,
                runID: runID
            )
            try Task.checkCancellation()

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
                    // interrupt() may have already written the terminal state
                    // for this exact run — its cancellation races with a
                    // network fetch that doesn't observe Task cancellation
                    // and runs to completion regardless. Don't re-terminate
                    // an already-terminal snapshot, which would otherwise
                    // duplicate the warning/log entry and push finishedAt
                    // later than when the user actually interrupted.
                    guard snapshot.status == .running else { return }
                    snapshot.status = .interrupted
                    snapshot.phase = .interrupted
                    snapshot.finishedAt = .now
                    snapshot.progress = nil
                }
                return
            }
            YamiboLog.sync.error("Favorite update check run \(runID) failed: \(error.localizedDescription)")
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
            YamiboLog.persistence.error("Failed to persist favorite update run snapshot \(snapshot.runID): \(error.localizedDescription)")
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
            // The fid filter only ever gets a row for items whose forum
            // actually resolved (see refreshFilters); an item stuck at
            // .unknown has no filter row it could be re-enabled through, so
            // disabling some OTHER forum must not silently exclude it too.
            let fidMatches: Bool
            if disabledFidsExist, case let .forumBoard(id, _) = item.sourceGroup {
                fidMatches = enabledFids.contains(id)
            } else {
                fidMatches = true
            }
            let categoryMatches = !disabledCategoriesExist || !Set(item.locations.compactMap(\.categoryID)).isDisjoint(with: enabledCategories)
            return fidMatches && categoryMatches
        }
    }

    private func replaceTrackedTargetsIfNeeded(_ candidates: [FavoriteItem]) async throws {
        let state = await updateStore.loadState()
        // `.mangaDirectory` tracked targets aren't keyed by any
        // `FavoriteItemTarget` in `candidates` (they're per-directory, not
        // per-favorite) — carry them through untouched instead of letting
        // this thread-lane-only replace wipe them out.
        let mangaDirectoryTargets = state.trackedTargets.filter {
            if case .mangaDirectory = $0.target { true } else { false }
        }
        let existingByID = Dictionary(uniqueKeysWithValues: state.trackedTargets.map { ($0.id, $0) })
        let targets = candidates.map { item -> FavoriteUpdateTrackedTarget in
            var existing = existingByID[item.target.id] ?? FavoriteUpdateTrackedTarget(
                target: .favorite(item.target),
                title: item.resolvedDisplayTitle,
                mode: FavoriteUpdateTargetMode(kind: item.target.kind)
            )
            existing.title = item.resolvedDisplayTitle
            existing.mode = FavoriteUpdateTargetMode(kind: item.target.kind)
            existing.categoryIDs = Set(item.locations.compactMap(\.categoryID))
            if case let .forumBoard(id, label) = item.sourceGroup {
                existing.fid = id
                existing.forumName = label
            }
            return existing
        }
        try await updateStore.replaceTrackedTargets(targets + mangaDirectoryTargets)
    }

    // MARK: - Single item check

    private enum CheckResult {
        case checked(detected: Int)
        case skipped
        case failed(String)
    }

    /// After this many consecutive failed check attempts, a target backs off
    /// to being retried at most once per `circuitBreakerCooldown` instead of
    /// on every single run — otherwise a permanently broken target (deleted
    /// thread, moved board) gets re-fetched forever with no end in sight.
    private static let circuitBreakerThreshold = 5
    private static let circuitBreakerCooldown: TimeInterval = 24 * 3600

    private func checkUpdate(for item: FavoriteItem) async -> CheckResult {
        let state = await updateStore.loadState()
        var target = state.trackedTargets.first { $0.target == .favorite(item.target) } ?? FavoriteUpdateTrackedTarget(
            target: .favorite(item.target),
            title: item.resolvedDisplayTitle,
            mode: FavoriteUpdateTargetMode(kind: item.target.kind)
        )

        if target.consecutiveFailures >= Self.circuitBreakerThreshold,
           let lastCheckedAt = target.lastCheckedAt,
           Date.now.timeIntervalSince(lastCheckedAt) < Self.circuitBreakerCooldown {
            return .skipped
        }

        let page: ForumThreadPage
        do {
            page = try await threadPage(for: item, knownPageCount: target.knownPageCount)
        } catch {
            YamiboLog.sync.warning("Failed to fetch thread page for favorite update check on \(item.target.id): \(error.localizedDescription)")
            target.consecutiveFailures += 1
            target.lastError = error.localizedDescription
            target.lastCheckedAt = .now
            try? await updateStore.upsertTrackedTarget(target)
            return .failed(error.localizedDescription)
        }

        await healUnknownSourceGroupIfNeeded(item: item, page: page)

        let fingerprint = FavoriteUpdateFingerprint(page: page)
        let previous = FavoriteUpdateFingerprint(target: target)

        // Only advance fields this fetch actually produced a value for — a
        // transient parse miss on one field must not erase a previously
        // known-good baseline, which would otherwise silently and
        // permanently break future comparisons for that field (the next
        // good fetch would compare against nil instead of the real prior
        // value, masking whatever changed in between).
        target.knownLatestPostID = fingerprint.latestPostID ?? target.knownLatestPostID
        target.knownReplyCount = fingerprint.replyCount ?? target.knownReplyCount
        target.knownPageCount = fingerprint.pageCount ?? target.knownPageCount
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

        guard previous.isReady, fingerprint.isNewer(than: previous) else {
            do {
                try await updateStore.upsertTrackedTarget(target)
                return .checked(detected: 0)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        let existingEvent = state.events.first { $0.target == .favorite(item.target) && $0.dismissedAt == nil }
        let summary = Self.mergedSummary(
            existing: existingEvent?.summary,
            new: FavoriteUpdateFingerprint.summary(from: previous, to: fingerprint)
        )
        let event = FavoriteUpdateEvent(
            target: .favorite(item.target),
            title: item.resolvedDisplayTitle,
            mode: FavoriteUpdateTargetMode(kind: item.target.kind),
            fid: target.fid,
            forumName: target.forumName,
            summary: summary,
            detailIDs: fingerprint.latestPostID.map { [$0] } ?? [],
            detectedAt: .now,
            ambiguous: fingerprint.latestPostID == nil
        )
        do {
            // Insert the event BEFORE advancing the persisted baseline: if
            // this throws, the target's stored baseline must not have moved,
            // so the next check re-derives the same delta and retries
            // instead of silently losing the detected update.
            try await updateStore.insertEvent(event)
            try await updateStore.upsertTrackedTarget(target)
            await deliverNotificationIfEnabled(for: event)
            return .checked(detected: 1)
        } catch {
            YamiboLog.persistence.error("Failed to persist tracked target or update event for \(item.target.id): \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Accumulates a newly detected delta onto an existing undismissed event
    /// for the same target instead of replacing it outright, so a user who
    /// misses several check cycles in a row sees the true accumulated total
    /// rather than only the most recent cycle's delta.
    private static func mergedSummary(existing: FavoriteUpdateSummary?, new: FavoriteUpdateSummary) -> FavoriteUpdateSummary {
        guard let existing else { return new }
        switch (existing, new) {
        case let (.newReplies(a), .newReplies(b)):
            return .newReplies(count: a + b)
        case let (.newPages(a), .newPages(b)):
            return .newPages(count: a + b)
        case let (.newChapters(a), .newChapters(b)):
            return .newChapters(count: a + b)
        default:
            return new
        }
    }

    /// Writes a resolved forum id/name back onto the favorite's own source
    /// group once a check successfully fetches its thread — items that never
    /// resolved a forum at add-time would otherwise stay `.unknown` forever,
    /// since nothing else in the app re-probes an already-favorited item.
    private func healUnknownSourceGroupIfNeeded(item: FavoriteItem, page: ForumThreadPage) async {
        guard item.sourceGroup == .unknown, let forumID = page.forumID ?? page.thread.fid else { return }
        guard var document = try? await libraryStore.load() else {
            YamiboLog.persistence.error("Failed to load favorite library while healing unknown source group for target \(item.target.id)")
            return
        }
        document.healUnknownSourceGroup(for: item.target, forumID: forumID, forumName: page.forumName)
        try? await libraryStore.save(document)
    }

    private func threadPage(for item: FavoriteItem, knownPageCount: Int?) async throws -> ForumThreadPage {
        if let pageFetcher {
            return try await pageFetcher(item)
        }
        guard let tid = item.target.threadID else {
            throw YamiboError.missingFavoriteThreadID
        }
        let repository = await makeForumThreadReaderRepository()
        let fid: String? = if case let .forumBoard(id, _) = item.sourceGroup { id } else { nil }
        let thread = ThreadIdentity(tid: tid, fid: fid)
        let context = ThreadNovelLaunchContext(thread: thread, title: item.resolvedDisplayTitle)
        // New replies land on the last page — fetching the previously
        // known last page (falling back to page 1 for a first-ever
        // check) is what lets latestPostID track the thread's actual
        // newest content instead of freezing at whatever was on page 1
        // forever once the thread grows past one page.
        let page = max(1, knownPageCount ?? 1)
        return try await repository.fetchThreadPage(context: context, page: page)
    }

    // MARK: - Smart-manga directory check lane

    /// One or more favorited `.mangaThread` chapters that resolved to the
    /// same `MangaDirectory`, collapsed into a single check unit (design
    /// decision #4: detection is per-directory, not per-favorite).
    private struct MangaDirectoryCandidate {
        var directory: MangaDirectory
        var forumID: String
        var forumName: String?
        var categoryIDs: Set<String>
    }

    private enum MangaDirectoryCheckResult {
        case checked(detected: Int)
        case skippedCircuitBreaker
        case skippedCooldown
        case failed(String)
    }

    /// Gathers eligible `.mangaThread` favorites (mode ON for their own
    /// board, per `BoardReaderSettings.isSmartComicModeEnabled` — the
    /// authoritative gate, never inferred from a resolved directory or any
    /// other proxy signal) and batch-resolves their tids to directories in
    /// ONE query, then groups the resolved ones by `cleanBookName`. A
    /// favorite whose board is mode-off, or whose tid has no resolved
    /// directory yet, is silently excluded here — not tracked, not an
    /// error; this pipeline never triggers directory resolution itself.
    private func mangaDirectoryGroups(in document: FavoriteLibraryDocument) async -> [MangaDirectoryCandidate] {
        guard let mangaDirectoryStore, let settingsStore else { return [] }
        let settings = await settingsStore.load()
        let eligibleItems: [(item: FavoriteItem, forumID: String)] = document.items.compactMap { item in
            guard item.target.kind == .mangaThread,
                  item.target.threadID != nil,
                  let forumID = item.forumID,
                  settings.isSmartComicModeEnabled(forumID: forumID) else { return nil }
            return (item, forumID)
        }
        guard !eligibleItems.isEmpty else { return [] }
        let tids = eligibleItems.compactMap { $0.item.target.threadID }
        let resolved: [String: MangaDirectory]
        do {
            resolved = try await mangaDirectoryStore.directories(containingTIDs: tids)
        } catch {
            YamiboLog.sync.warning("Failed to batch-resolve manga directories for update checking: \(error.localizedDescription)")
            return []
        }
        guard !resolved.isEmpty else { return [] }

        var groupsByName: [String: MangaDirectoryCandidate] = [:]
        for (item, forumID) in eligibleItems.sorted(by: { $0.item.target.id < $1.item.target.id }) {
            guard let tid = item.target.threadID, let directory = resolved[tid] else { continue }
            var group = groupsByName[directory.cleanBookName] ?? MangaDirectoryCandidate(
                directory: directory,
                forumID: forumID,
                forumName: item.forumName,
                categoryIDs: []
            )
            group.categoryIDs.formUnion(item.locations.compactMap(\.categoryID))
            groupsByName[directory.cleanBookName] = group
        }
        return groupsByName.values.sorted { $0.directory.cleanBookName < $1.directory.cleanBookName }
    }

    /// Seeds, then (for already-tracked, due groups) refreshes and diffs
    /// smart-manga directories. Ordering/capping (design point g/h): every
    /// never-seen-before group is seeded first (zero network cost, always
    /// allowed), then ALL due `.tag`-strategy groups run (cheap, no search
    /// cooldown in the common case), then up to `nonTagCheckCap` due
    /// non-`.tag`-strategy groups run oldest-`lastCheckedAt`-first. A
    /// cooldown/flood-control hit stops further groups of either kind for
    /// the rest of this run — the cooldown is global, so trying another
    /// would just fail again and waste the run's remaining budget.
    private func checkMangaDirectoryGroups(
        _ groups: [MangaDirectoryCandidate],
        nonTagCheckCap: Int,
        runID: String
    ) async {
        guard !groups.isEmpty else { return }
        let state = await updateStore.loadState()
        let existingByCleanBookName: [String: FavoriteUpdateTrackedTarget] = Dictionary(
            uniqueKeysWithValues: state.trackedTargets.compactMap { target in
                guard case let .mangaDirectory(cleanBookName) = target.target else { return nil }
                return (cleanBookName, target)
            }
        )

        let newGroups = groups.filter { existingByCleanBookName[$0.directory.cleanBookName] == nil }
        for group in newGroups {
            guard !Task.isCancelled else { return }
            await seedMangaDirectoryBaseline(group)
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.totalCount += 1
                snapshot.completedCount += 1
            }
        }

        guard let interval = await smartMangaInterval(),
              let delay = interval.nextDelay(hasRecentEvents: hasRecentMangaDirectoryEvents) else {
            return
        }

        let dueExisting: [(group: MangaDirectoryCandidate, existing: FavoriteUpdateTrackedTarget)] = groups.compactMap { group in
            guard let existing = existingByCleanBookName[group.directory.cleanBookName] else { return nil }
            if let lastCheckedAt = existing.lastCheckedAt, Date.now.timeIntervalSince(lastCheckedAt) < delay {
                return nil
            }
            return (group, existing)
        }

        let tagDue = dueExisting.filter { $0.group.directory.strategy == .tag }
        let nonTagDue = dueExisting
            .filter { $0.group.directory.strategy != .tag }
            .sorted { ($0.existing.lastCheckedAt ?? .distantPast) < ($1.existing.lastCheckedAt ?? .distantPast) }

        for (group, existing) in tagDue {
            guard !Task.isCancelled else { return }
            await updateSnapshot(runID: runID) { snapshot in snapshot.totalCount += 1 }
            let result = await checkMangaDirectoryUpdate(group: group, existing: existing)
            await applyMangaDirectoryResult(result, runID: runID)
            if case .skippedCooldown = result {
                break
            }
        }

        var nonTagChecksPerformed = 0
        for (group, existing) in nonTagDue {
            guard !Task.isCancelled else { return }
            guard nonTagChecksPerformed < nonTagCheckCap else { break }
            nonTagChecksPerformed += 1
            await updateSnapshot(runID: runID) { snapshot in snapshot.totalCount += 1 }
            let result = await checkMangaDirectoryUpdate(group: group, existing: existing)
            await applyMangaDirectoryResult(result, runID: runID)
            if case .skippedCooldown = result {
                break
            }
        }
    }

    private func smartMangaInterval() async -> SmartMangaUpdateCheckInterval? {
        guard let settingsStore else { return nil }
        return await settingsStore.load().favorites.smartMangaUpdateCheckInterval
    }

    /// First sighting of a directory: baseline-only, zero network, no event
    /// (design point 6 — otherwise every already-read chapter would report
    /// as "new" the moment tracking starts).
    private func seedMangaDirectoryBaseline(_ group: MangaDirectoryCandidate) async {
        let target = FavoriteUpdateTrackedTarget(
            target: .mangaDirectory(cleanBookName: group.directory.cleanBookName),
            title: group.directory.cleanBookName,
            mode: .mangaDirectory,
            categoryIDs: group.categoryIDs,
            fid: group.forumID,
            forumName: group.forumName,
            knownChapterTIDs: Set(group.directory.chapters.map(\.tid)),
            baselineReady: true,
            lastCheckedAt: .now
        )
        try? await updateStore.upsertTrackedTarget(target)
    }

    private func applyMangaDirectoryResult(_ result: MangaDirectoryCheckResult, runID: String) async {
        switch result {
        case let .checked(detected):
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.completedCount += 1
                snapshot.detectedCount += detected
            }
        case .skippedCircuitBreaker, .skippedCooldown:
            await updateSnapshot(runID: runID) { snapshot in snapshot.skippedCount += 1 }
        case let .failed(message):
            await updateSnapshot(runID: runID) { snapshot in
                snapshot.failedCount += 1
                snapshot.warningMessage = [snapshot.warningMessage, message].compactMap { $0 }.joined(separator: "\n")
            }
        }
    }

    /// Refreshes one directory's chapter list over the network and diffs the
    /// result against the tracked tid baseline. `YamiboError.searchCooldown`
    /// (the workflow's own client-side cooldown) and `.floodControl` (the
    /// forum's own flood-control page, detected downstream in the parser)
    /// are both an expected "not now" — never fed to the circuit breaker,
    /// never advancing the baseline. Any other error DOES feed the breaker,
    /// same as the thread-check lane.
    private func checkMangaDirectoryUpdate(
        group: MangaDirectoryCandidate,
        existing: FavoriteUpdateTrackedTarget
    ) async -> MangaDirectoryCheckResult {
        guard let makeMangaDirectoryWorkflow else { return .skippedCircuitBreaker }
        var target = existing

        if target.consecutiveFailures >= Self.circuitBreakerThreshold,
           let lastCheckedAt = target.lastCheckedAt,
           Date.now.timeIntervalSince(lastCheckedAt) < Self.circuitBreakerCooldown {
            return .skippedCircuitBreaker
        }

        let workflow = await makeMangaDirectoryWorkflow(group.forumID)
        // Seeds the search keyword from a real chapter title when the
        // directory has none yet — any favorited chapter in the group works,
        // so the most recently added one is as good a representative as any.
        let representativeTID = group.directory.chapters.last?.tid

        do {
            let result = try await workflow.updateDirectory(group.directory, currentTID: representativeTID)
            // `existing` is only ever produced by `seedMangaDirectoryBaseline`
            // or a prior pass through this same function, both of which
            // always set `knownChapterTIDs` — the `?? []` here just satisfies
            // the optional, it never actually triggers.
            let knownTIDs = target.knownChapterTIDs ?? []
            let refreshedTIDs = Set(result.directory.chapters.map(\.tid))
            let newTIDs = refreshedTIDs.subtracting(knownTIDs)

            target.knownChapterTIDs = knownTIDs.union(refreshedTIDs)
            target.baselineReady = true
            target.lastCheckedAt = .now
            target.lastError = nil
            target.consecutiveFailures = 0
            target.title = group.directory.cleanBookName
            target.fid = group.forumID
            target.forumName = group.forumName
            target.categoryIDs = group.categoryIDs

            guard !newTIDs.isEmpty else {
                try? await updateStore.upsertTrackedTarget(target)
                return .checked(detected: 0)
            }

            let key = FavoriteUpdateTargetKey.mangaDirectory(cleanBookName: group.directory.cleanBookName)
            let state = await updateStore.loadState()
            let existingEvent = state.events.first { $0.target == key && $0.dismissedAt == nil }
            let summary = Self.mergedSummary(
                existing: existingEvent?.summary,
                new: .newChapters(count: newTIDs.count)
            )
            let event = FavoriteUpdateEvent(
                target: key,
                title: group.directory.cleanBookName,
                mode: .mangaDirectory,
                fid: group.forumID,
                forumName: group.forumName,
                summary: summary,
                detailIDs: newTIDs.sorted(),
                detectedAt: .now,
                ambiguous: false
            )
            try await updateStore.insertEvent(event)
            try await updateStore.upsertTrackedTarget(target)
            await deliverNotificationIfEnabled(for: event)
            return .checked(detected: 1)
        } catch {
            if case YamiboError.searchCooldown = error {
                YamiboLog.sync.info("Smart-manga directory check for \(group.directory.cleanBookName) hit search cooldown, deferring")
                return .skippedCooldown
            }
            if case YamiboError.floodControl = error {
                YamiboLog.sync.warning("Smart-manga directory check for \(group.directory.cleanBookName) hit forum flood control, deferring")
                return .skippedCooldown
            }
            YamiboLog.sync.warning("Smart-manga directory check failed for \(group.directory.cleanBookName): \(error.localizedDescription)")
            target.consecutiveFailures += 1
            target.lastError = error.localizedDescription
            target.lastCheckedAt = .now
            try? await updateStore.upsertTrackedTarget(target)
            return .failed(error.localizedDescription)
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
