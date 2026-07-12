import Foundation

/// Descriptive label mirroring the tracked target's kind.
/// `.normalThread`/`.novelThread`/`.mangaThread` map 1:1 from
/// `FavoriteItemTargetKind` via `init(kind:)` so a favorite is never
/// mislabeled. `.mangaThread` is still unreached at runtime:
/// per-favorite update checking's candidate filter
/// (`FavoriteUpdateMonitor.candidates(in:)`) excludes `.mangaThread`
/// favorites entirely — the case is kept only for kind-parity so
/// `init(kind:)` stays a total mapping.
///
/// `.mangaDirectory` is a DIFFERENT thing, added for smart-manga chapter
/// checking: it labels a *directory-level* tracked target/event, which has
/// no single favorite kind to map from (multiple `.mangaThread` favorites
/// that resolve to the same `MangaDirectory` collapse into one). It is only
/// ever constructed directly (never via `init(kind:)`) and paired with
/// `FavoriteUpdateTargetKey.mangaDirectory`.
public enum FavoriteUpdateTargetMode: String, Codable, Hashable, Sendable {
    case normalThread
    case novelThread
    case mangaThread
    case mangaDirectory

    public init(kind: FavoriteItemTargetKind) {
        switch kind {
        case .normalThread:
            self = .normalThread
        case .novelThread:
            self = .novelThread
        case .mangaThread:
            self = .mangaThread
        }
    }
}

/// Identifies what a tracked target / event is about. Thread-mode checking
/// (`.normalThread`/`.novelThread` favorites) keys off the individual
/// favorite's own `FavoriteItemTarget`. Smart-manga chapter checking keys
/// off the `MangaDirectory` itself (`cleanBookName`) instead: multiple
/// favorited chapters that resolve to the same directory collapse into ONE
/// tracked target / ONE potential event, mirroring how the favorites page
/// already merges them into one card (see design decision #4 in the
/// smart-manga update-check plan).
public enum FavoriteUpdateTargetKey: Codable, Hashable, Sendable {
    case favorite(FavoriteItemTarget)
    case mangaDirectory(cleanBookName: String)

    private static let mangaDirectoryIDPrefix = "manga-directory:"

    public var id: String {
        switch self {
        case let .favorite(target):
            target.id
        case let .mangaDirectory(cleanBookName):
            "\(Self.mangaDirectoryIDPrefix)\(cleanBookName)"
        }
    }

    /// Reverses `.mangaDirectory(cleanBookName:).id` for callers (e.g.
    /// notification tap-routing) that only have the persisted id string, not
    /// the original enum case. Returns nil for a `.favorite` id, never
    /// guesses — the single source of truth for the prefix stays `id` above.
    public static func mangaDirectoryCleanBookName(fromID id: String) -> String? {
        guard id.hasPrefix(mangaDirectoryIDPrefix) else { return nil }
        return String(id.dropFirst(mangaDirectoryIDPrefix.count))
    }
}

public enum FavoriteUpdateRunStatus: String, Codable, Hashable, Sendable {
    case running
    case interrupted
    case failed
    case completed
    case canceled
}

public enum FavoriteUpdateRunPhase: String, Codable, Hashable, Sendable {
    case preparing
    case checking
    case interrupted
    case failed
    case completed
    case canceled
}

/// Transient progress detail for a running update check, beyond what
/// `FavoriteUpdateRunPhase` conveys. The presentation layer maps these to
/// localized text; the model never stores display copy.
public enum FavoriteUpdateRunProgress: Codable, Hashable, Sendable {
    case loadedTargets(count: Int)
    case checking(index: Int, total: Int, title: String)
}

public struct FavoriteUpdateRunSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var runID: String
    public var status: FavoriteUpdateRunStatus
    public var phase: FavoriteUpdateRunPhase
    public var startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var totalCount: Int
    public var completedCount: Int
    public var skippedCount: Int
    public var failedCount: Int
    public var detectedCount: Int
    public var progress: FavoriteUpdateRunProgress?
    /// Raw error descriptions from failed operations; unlike `progress` these
    /// carry free-form error text, not display copy.
    public var warningMessage: String?
    public var errorMessage: String?

    public var id: String { runID }

    public init(
        runID: String = UUID().uuidString,
        status: FavoriteUpdateRunStatus = .running,
        phase: FavoriteUpdateRunPhase = .preparing,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        finishedAt: Date? = nil,
        totalCount: Int = 0,
        completedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0,
        detectedCount: Int = 0,
        progress: FavoriteUpdateRunProgress? = nil,
        warningMessage: String? = nil,
        errorMessage: String? = nil
    ) {
        self.runID = runID
        self.status = status
        self.phase = phase
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.detectedCount = detectedCount
        self.progress = progress
        self.warningMessage = warningMessage
        self.errorMessage = errorMessage
    }
}

public struct FavoriteUpdateTrackedTarget: Codable, Hashable, Identifiable, Sendable {
    public var target: FavoriteUpdateTargetKey
    public var title: String
    public var mode: FavoriteUpdateTargetMode
    public var categoryIDs: Set<String>
    public var fid: String?
    public var forumName: String?
    public var knownLatestPostID: String?
    public var knownReplyCount: Int?
    public var knownPageCount: Int?
    /// Chapter-tid baseline for `.mangaDirectory` targets only — always nil
    /// for thread-mode targets. Monotonic: only ever grows (set union), even
    /// though `MangaDirectoryWorkflow.updateDirectory`'s own retention logic
    /// can prune stale chapters from the directory's stored list independent
    /// of this baseline — shrinking the baseline in lockstep with that
    /// pruning would make a pruned-then-reappearing chapter falsely
    /// re-report as new.
    public var knownChapterTIDs: Set<String>?
    public var baselineReady: Bool
    public var lastCheckedAt: Date?
    public var lastUpdatedAt: Date?
    public var lastError: String?
    public var consecutiveFailures: Int

    public var id: String { target.id }

    public init(
        target: FavoriteUpdateTargetKey,
        title: String,
        mode: FavoriteUpdateTargetMode,
        categoryIDs: Set<String> = [],
        fid: String? = nil,
        forumName: String? = nil,
        knownLatestPostID: String? = nil,
        knownReplyCount: Int? = nil,
        knownPageCount: Int? = nil,
        knownChapterTIDs: Set<String>? = nil,
        baselineReady: Bool = false,
        lastCheckedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        lastError: String? = nil,
        consecutiveFailures: Int = 0
    ) {
        self.target = target
        self.title = title
        self.mode = mode
        self.categoryIDs = categoryIDs
        self.fid = fid?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.forumName = forumName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.knownLatestPostID = knownLatestPostID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.knownReplyCount = knownReplyCount
        self.knownPageCount = knownPageCount
        self.knownChapterTIDs = knownChapterTIDs
        self.baselineReady = baselineReady
        self.lastCheckedAt = lastCheckedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.lastError = lastError
        self.consecutiveFailures = consecutiveFailures
    }
}

/// What changed for a tracked favorite between two update checks.
public enum FavoriteUpdateSummary: Codable, Hashable, Sendable {
    case newReplies(count: Int)
    case newPages(count: Int)
    /// New chapter-thread tids found for a `.mangaDirectory` target — the
    /// directory-mode counterpart of `.newReplies`/`.newPages`.
    case newChapters(count: Int)
    case changed
}

public struct FavoriteUpdateEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var target: FavoriteUpdateTargetKey
    public var title: String
    public var mode: FavoriteUpdateTargetMode
    public var fid: String?
    public var forumName: String?
    public var summary: FavoriteUpdateSummary
    public var detailIDs: [String]
    public var detectedAt: Date
    public var readAt: Date?
    public var dismissedAt: Date?
    public var ambiguous: Bool

    public init(
        id: String = UUID().uuidString,
        target: FavoriteUpdateTargetKey,
        title: String,
        mode: FavoriteUpdateTargetMode,
        fid: String? = nil,
        forumName: String? = nil,
        summary: FavoriteUpdateSummary,
        detailIDs: [String] = [],
        detectedAt: Date = .now,
        readAt: Date? = nil,
        dismissedAt: Date? = nil,
        ambiguous: Bool = false
    ) {
        self.id = id
        self.target = target
        self.title = title
        self.mode = mode
        self.fid = fid
        self.forumName = forumName
        self.summary = summary
        self.detailIDs = detailIDs
        self.detectedAt = detectedAt
        self.readAt = readAt
        self.dismissedAt = dismissedAt
        self.ambiguous = ambiguous
    }
}

public struct FavoriteUpdateFidFilter: Codable, Hashable, Identifiable, Sendable {
    public var fid: String
    public var forumName: String
    public var enabled: Bool
    public var itemCount: Int
    public var updatedAt: Date

    public var id: String { fid }

    public init(fid: String, forumName: String, enabled: Bool = true, itemCount: Int = 0, updatedAt: Date = .now) {
        self.fid = fid
        self.forumName = forumName
        self.enabled = enabled
        self.itemCount = itemCount
        self.updatedAt = updatedAt
    }
}

public struct FavoriteUpdateCategoryFilter: Codable, Hashable, Identifiable, Sendable {
    public var categoryID: String
    public var categoryName: String
    public var enabled: Bool
    public var itemCount: Int
    public var updatedAt: Date

    public var id: String { categoryID }

    public init(categoryID: String, categoryName: String, enabled: Bool = true, itemCount: Int = 0, updatedAt: Date = .now) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.enabled = enabled
        self.itemCount = itemCount
        self.updatedAt = updatedAt
    }
}

public struct FavoriteUpdateStoreState: Codable, Hashable, Sendable {
    public var trackedTargets: [FavoriteUpdateTrackedTarget]
    public var events: [FavoriteUpdateEvent]
    public var runs: [FavoriteUpdateRunSnapshot]
    public var fidFilters: [FavoriteUpdateFidFilter]
    public var categoryFilters: [FavoriteUpdateCategoryFilter]

    public init(
        trackedTargets: [FavoriteUpdateTrackedTarget] = [],
        events: [FavoriteUpdateEvent] = [],
        runs: [FavoriteUpdateRunSnapshot] = [],
        fidFilters: [FavoriteUpdateFidFilter] = [],
        categoryFilters: [FavoriteUpdateCategoryFilter] = []
    ) {
        self.trackedTargets = trackedTargets
        self.events = events
        self.runs = runs
        self.fidFilters = fidFilters
        self.categoryFilters = categoryFilters
    }
}

public actor FavoriteUpdateStore {
    public static let didChangeNotification = Notification.Name("yamibo.favoriteUpdateStore.didChange")
    public static let changeIDUserInfoKey = "changeID"
    public static let defaultKey = "yamibo.favoriteUpdates"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = FavoriteUpdateStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func loadState() async -> FavoriteUpdateStoreState {
        loadStateSync()
    }

    public func latestRun() async -> FavoriteUpdateRunSnapshot? {
        loadStateSync().runs.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    public func activeEvents() async -> [FavoriteUpdateEvent] {
        loadStateSync().events
            .filter { $0.dismissedAt == nil }
            .sorted { lhs, rhs in
                if lhs.detectedAt != rhs.detectedAt { return lhs.detectedAt > rhs.detectedAt }
                return lhs.id > rhs.id
            }
    }

    public func saveRun(_ snapshot: FavoriteUpdateRunSnapshot) async throws {
        var state = loadStateSync()
        state.runs.removeAll { $0.runID == snapshot.runID }
        state.runs.append(snapshot)
        state.runs = Array(state.runs.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
        try persist(state)
    }

    public func upsertTrackedTarget(_ target: FavoriteUpdateTrackedTarget) async throws {
        var state = loadStateSync()
        state.trackedTargets.removeAll { $0.id == target.id }
        state.trackedTargets.append(target)
        try persist(state)
    }

    public func replaceTrackedTargets(_ targets: [FavoriteUpdateTrackedTarget]) async throws {
        var state = loadStateSync()
        state.trackedTargets = targets.sorted { $0.id < $1.id }
        try persist(state)
    }

    public func insertEvent(_ event: FavoriteUpdateEvent) async throws {
        var state = loadStateSync()
        state.events.removeAll { $0.target == event.target && $0.dismissedAt == nil }
        state.events.append(event)
        try persist(state)
    }

    /// Migrates a `.mangaDirectory` tracked target and its events from
    /// `oldCleanBookName` to `newCleanBookName` when `MangaDirectoryStore`
    /// renames/merges a directory (its 5th rename-cascade step). Unlike the
    /// GRDB-backed `ContentCoverStore`/`LikeStore` cascades this store
    /// mirrors, this store is UserDefaults-backed and cannot join the same
    /// database transaction — the caller invokes this as a best-effort
    /// follow-up after the GRDB write commits, not atomically with it.
    /// A rename that merges into an ALREADY-tracked `newCleanBookName`
    /// unions the two known-chapter-tid baselines (never shrinks either
    /// side) and keeps only the more recently detected of any two
    /// now-colliding undismissed events for the merged target.
    public func renameMangaDirectoryTracking(from oldCleanBookName: String, to newCleanBookName: String) async throws {
        guard oldCleanBookName != newCleanBookName else { return }
        var state = loadStateSync()
        let oldKey = FavoriteUpdateTargetKey.mangaDirectory(cleanBookName: oldCleanBookName)
        let newKey = FavoriteUpdateTargetKey.mangaDirectory(cleanBookName: newCleanBookName)

        if let oldTarget = state.trackedTargets.first(where: { $0.target == oldKey }) {
            state.trackedTargets.removeAll { $0.target == oldKey }
            if let existingIndex = state.trackedTargets.firstIndex(where: { $0.target == newKey }) {
                var merged = state.trackedTargets[existingIndex]
                merged.knownChapterTIDs = (merged.knownChapterTIDs ?? []).union(oldTarget.knownChapterTIDs ?? [])
                merged.categoryIDs.formUnion(oldTarget.categoryIDs)
                state.trackedTargets[existingIndex] = merged
            } else {
                var renamed = oldTarget
                renamed.target = newKey
                renamed.title = newCleanBookName
                state.trackedTargets.append(renamed)
            }
        }

        state.events = state.events.map { event in
            guard event.target == oldKey else { return event }
            var renamed = event
            renamed.target = newKey
            renamed.title = newCleanBookName
            return renamed
        }
        var seenActiveTargetIDs: Set<String> = []
        state.events = state.events
            .sorted { $0.detectedAt > $1.detectedAt }
            .filter { event in
                guard event.dismissedAt == nil else { return true }
                return seenActiveTargetIDs.insert(event.target.id).inserted
            }

        try persist(state)
    }

    public func markEventRead(_ id: String, date: Date = .now) async throws {
        var state = loadStateSync()
        guard let index = state.events.firstIndex(where: { $0.id == id }) else { return }
        state.events[index].readAt = date
        try persist(state)
    }

    public func dismissEvent(_ id: String, date: Date = .now) async throws {
        var state = loadStateSync()
        guard let index = state.events.firstIndex(where: { $0.id == id }) else { return }
        state.events[index].dismissedAt = date
        try persist(state)
    }

    public func dismissAllEvents(date: Date = .now) async throws {
        var state = loadStateSync()
        for index in state.events.indices where state.events[index].dismissedAt == nil {
            state.events[index].dismissedAt = date
        }
        try persist(state)
    }

    public func replaceFilters(
        fidFilters: [FavoriteUpdateFidFilter],
        categoryFilters: [FavoriteUpdateCategoryFilter]
    ) async throws {
        var state = loadStateSync()
        let previousFids = Dictionary(uniqueKeysWithValues: state.fidFilters.map { ($0.fid, $0.enabled) })
        let previousCategories = Dictionary(uniqueKeysWithValues: state.categoryFilters.map { ($0.categoryID, $0.enabled) })
        state.fidFilters = fidFilters.map { filter in
            FavoriteUpdateFidFilter(
                fid: filter.fid,
                forumName: filter.forumName,
                enabled: previousFids[filter.fid] ?? filter.enabled,
                itemCount: filter.itemCount,
                updatedAt: filter.updatedAt
            )
        }
        state.categoryFilters = categoryFilters.map { filter in
            FavoriteUpdateCategoryFilter(
                categoryID: filter.categoryID,
                categoryName: filter.categoryName,
                enabled: previousCategories[filter.categoryID] ?? filter.enabled,
                itemCount: filter.itemCount,
                updatedAt: filter.updatedAt
            )
        }
        try persist(state)
    }

    public func setFidEnabled(_ fid: String, enabled: Bool, date: Date = .now) async throws {
        var state = loadStateSync()
        guard let index = state.fidFilters.firstIndex(where: { $0.fid == fid }) else { return }
        state.fidFilters[index].enabled = enabled
        state.fidFilters[index].updatedAt = date
        try persist(state)
    }

    public func setCategoryEnabled(_ categoryID: String, enabled: Bool, date: Date = .now) async throws {
        var state = loadStateSync()
        guard let index = state.categoryFilters.firstIndex(where: { $0.categoryID == categoryID }) else { return }
        state.categoryFilters[index].enabled = enabled
        state.categoryFilters[index].updatedAt = date
        try persist(state)
    }

    private func loadStateSync() -> FavoriteUpdateStoreState {
        guard let data = defaults.data(forKey: key) else {
            return FavoriteUpdateStoreState()
        }
        do {
            return try decoder.decode(FavoriteUpdateStoreState.self, from: data)
        } catch {
            YamiboLog.library.error("Failed to decode stored favorite update tracking state, resetting to empty state: \(error)")
            return FavoriteUpdateStoreState()
        }
    }

    private func persist(_ state: FavoriteUpdateStoreState) throws {
        do {
            defaults.set(try encoder.encode(state), forKey: key)
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
