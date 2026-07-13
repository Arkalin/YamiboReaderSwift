import Foundation
@preconcurrency import GRDB

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
    private static let keptRunCount = 10
    nonisolated(unsafe) private static var databasePoolCache: [String: DatabasePool] = [:]
    private static let databasePoolCacheLock = NSLock()

    public nonisolated let changeID = UUID().uuidString

    private let database: DatabasePool

    /// Convenience for tests/previews, mirroring `FavoriteLibraryStore`:
    /// `.standard` resolves the shared `yamibo.sqlite` pool; any other
    /// defaults suite gets its own temporary database keyed by `key`.
    public init(defaults: UserDefaults = .standard, key: String = "yamibo.favoriteUpdates") {
        self.database = Self.openDatabase(defaults: defaults, key: key)
    }

    init(databasePool: DatabasePool) {
        self.database = databasePool
    }

    private static func openDatabase(defaults: UserDefaults, key: String) -> DatabasePool {
        do {
            if defaults === UserDefaults.standard {
                return try cachedDatabasePool(rootDirectory: YamiboDatabase.defaultRootDirectory())
            }
            let idKey = "\(key).grdbDatabaseID"
            let databaseID: String
            if let existing = defaults.string(forKey: idKey), !existing.isEmpty {
                databaseID = existing
            } else {
                databaseID = UUID().uuidString
                defaults.set(databaseID, forKey: idKey)
            }
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("YamiboReaderFavoriteUpdates", isDirectory: true)
                .appendingPathComponent(databaseID, isDirectory: true)
            return try cachedDatabasePool(rootDirectory: root)
        } catch {
            fatalError("Failed to open FavoriteUpdateStore database: \(error)")
        }
    }

    private static func cachedDatabasePool(rootDirectory: URL) throws -> DatabasePool {
        let key = rootDirectory.standardizedFileURL.path
        databasePoolCacheLock.lock()
        defer { databasePoolCacheLock.unlock() }
        if let pool = databasePoolCache[key] {
            return pool
        }

        let pool = try YamiboDatabase.openPool(rootDirectory: rootDirectory)
        databasePoolCache[key] = pool
        return pool
    }

    public func loadState() async -> FavoriteUpdateStoreState {
        do {
            return try await database.read { db in try Self.state(in: db) }
        } catch {
            YamiboLog.library.error("Failed to load stored favorite update tracking state, returning empty state: \(error)")
            return FavoriteUpdateStoreState()
        }
    }

    public func latestRun() async -> FavoriteUpdateRunSnapshot? {
        try? await database.read { db in
            guard let json = try String.fetchOne(
                db,
                sql: """
                SELECT run_json FROM favorite_update_runs
                ORDER BY updated_at DESC, run_id DESC
                LIMIT 1
                """
            ) else {
                return nil
            }
            return try Self.decode(FavoriteUpdateRunSnapshot.self, from: json)
        }
    }

    public func activeEvents() async -> [FavoriteUpdateEvent] {
        (try? await database.read { db in try Self.activeEvents(in: db) }) ?? []
    }

    public func saveRun(_ snapshot: FavoriteUpdateRunSnapshot) async throws {
        try await write { db in
            try db.execute(
                sql: """
                INSERT INTO favorite_update_runs (run_id, updated_at, run_json)
                VALUES (?, ?, ?)
                ON CONFLICT(run_id) DO UPDATE SET
                    updated_at = excluded.updated_at,
                    run_json = excluded.run_json
                """,
                arguments: [snapshot.runID, snapshot.updatedAt.timeIntervalSince1970, try Self.encode(snapshot)]
            )
            try db.execute(
                sql: """
                DELETE FROM favorite_update_runs
                WHERE run_id NOT IN (
                    SELECT run_id FROM favorite_update_runs
                    ORDER BY updated_at DESC, run_id DESC
                    LIMIT ?
                )
                """,
                arguments: [Self.keptRunCount]
            )
            return true
        }
    }

    public func upsertTrackedTarget(_ target: FavoriteUpdateTrackedTarget) async throws {
        try await write { db in
            try Self.upsertTrackedTarget(target, in: db)
            return true
        }
    }

    public func replaceTrackedTargets(_ targets: [FavoriteUpdateTrackedTarget]) async throws {
        try await write { db in
            try db.execute(sql: "DELETE FROM favorite_update_tracked_targets")
            for target in targets {
                try Self.upsertTrackedTarget(target, in: db)
            }
            return true
        }
    }

    public func insertEvent(_ event: FavoriteUpdateEvent) async throws {
        try await write { db in
            try db.execute(
                sql: "DELETE FROM favorite_update_events WHERE target_id = ? AND dismissed_at IS NULL",
                arguments: [event.target.id]
            )
            try Self.insertEventRow(event, in: db)
            return true
        }
    }

    /// Migrates a `.mangaDirectory` tracked target and its events from
    /// `oldCleanBookName` to `newCleanBookName` when `MangaDirectoryStore`
    /// renames/merges a directory. `MangaDirectoryStore` runs the static
    /// variant inside its own rename transaction; this instance method exists
    /// for callers outside that cascade.
    public func renameMangaDirectoryTracking(from oldCleanBookName: String, to newCleanBookName: String) async throws {
        guard oldCleanBookName != newCleanBookName else { return }
        try await write { db in
            try Self.renameMangaDirectoryTracking(from: oldCleanBookName, to: newCleanBookName, in: db)
            return true
        }
    }

    /// A rename that merges into an ALREADY-tracked `newCleanBookName`
    /// unions the two known-chapter-tid baselines (never shrinks either
    /// side) and keeps only the more recently detected of any two
    /// now-colliding undismissed events for the merged target.
    public static func renameMangaDirectoryTracking(
        from oldCleanBookName: String,
        to newCleanBookName: String,
        in db: Database
    ) throws {
        guard oldCleanBookName != newCleanBookName else { return }
        let oldKey = FavoriteUpdateTargetKey.mangaDirectory(cleanBookName: oldCleanBookName)
        let newKey = FavoriteUpdateTargetKey.mangaDirectory(cleanBookName: newCleanBookName)

        if let oldTarget = try trackedTarget(id: oldKey.id, in: db) {
            try db.execute(
                sql: "DELETE FROM favorite_update_tracked_targets WHERE target_id = ?",
                arguments: [oldKey.id]
            )
            if var merged = try trackedTarget(id: newKey.id, in: db) {
                merged.knownChapterTIDs = (merged.knownChapterTIDs ?? []).union(oldTarget.knownChapterTIDs ?? [])
                merged.categoryIDs.formUnion(oldTarget.categoryIDs)
                try upsertTrackedTarget(merged, in: db)
            } else {
                var renamed = oldTarget
                renamed.target = newKey
                renamed.title = newCleanBookName
                try upsertTrackedTarget(renamed, in: db)
            }
        }

        let oldEventRows = try Row.fetchAll(
            db,
            sql: "SELECT id, event_json FROM favorite_update_events WHERE target_id = ?",
            arguments: [oldKey.id]
        )
        for row in oldEventRows {
            var event = try decode(FavoriteUpdateEvent.self, from: row["event_json"] as String)
            event.target = newKey
            event.title = newCleanBookName
            try db.execute(
                sql: "UPDATE favorite_update_events SET target_id = ?, event_json = ? WHERE id = ?",
                arguments: [newKey.id, try encode(event), row["id"] as String]
            )
        }

        // The one-undismissed-event-per-target invariant can only break for
        // the merged target; keep the most recently detected event.
        let collidingIDs = try String.fetchAll(
            db,
            sql: """
            SELECT id FROM favorite_update_events
            WHERE target_id = ? AND dismissed_at IS NULL
            ORDER BY detected_at DESC, id DESC
            """,
            arguments: [newKey.id]
        )
        for id in collidingIDs.dropFirst() {
            try db.execute(sql: "DELETE FROM favorite_update_events WHERE id = ?", arguments: [id])
        }
    }

    public func markEventRead(_ id: String, date: Date = .now) async throws {
        try await write { db in
            guard var event = try Self.event(id: id, in: db) else { return false }
            event.readAt = date
            try db.execute(
                sql: "UPDATE favorite_update_events SET event_json = ? WHERE id = ?",
                arguments: [try Self.encode(event), id]
            )
            return true
        }
    }

    public func dismissEvent(_ id: String, date: Date = .now) async throws {
        try await write { db in
            guard var event = try Self.event(id: id, in: db) else { return false }
            event.dismissedAt = date
            try db.execute(
                sql: "UPDATE favorite_update_events SET dismissed_at = ?, event_json = ? WHERE id = ?",
                arguments: [date.timeIntervalSince1970, try Self.encode(event), id]
            )
            return true
        }
    }

    public func dismissAllEvents(date: Date = .now) async throws {
        try await write { db in
            for var event in try Self.activeEvents(in: db) {
                event.dismissedAt = date
                try db.execute(
                    sql: "UPDATE favorite_update_events SET dismissed_at = ?, event_json = ? WHERE id = ?",
                    arguments: [date.timeIntervalSince1970, try Self.encode(event), event.id]
                )
            }
            return true
        }
    }

    public func replaceFilters(
        fidFilters: [FavoriteUpdateFidFilter],
        categoryFilters: [FavoriteUpdateCategoryFilter]
    ) async throws {
        try await write { db in
            let previousFids = Dictionary(uniqueKeysWithValues: try Self.fidFilters(in: db).map { ($0.fid, $0.enabled) })
            let previousCategories = Dictionary(uniqueKeysWithValues: try Self.categoryFilters(in: db).map { ($0.categoryID, $0.enabled) })
            try db.execute(sql: "DELETE FROM favorite_update_fid_filters")
            for (index, filter) in fidFilters.enumerated() {
                let resolved = FavoriteUpdateFidFilter(
                    fid: filter.fid,
                    forumName: filter.forumName,
                    enabled: previousFids[filter.fid] ?? filter.enabled,
                    itemCount: filter.itemCount,
                    updatedAt: filter.updatedAt
                )
                try Self.insertFidFilterRow(resolved, order: index, in: db)
            }
            try db.execute(sql: "DELETE FROM favorite_update_category_filters")
            for (index, filter) in categoryFilters.enumerated() {
                let resolved = FavoriteUpdateCategoryFilter(
                    categoryID: filter.categoryID,
                    categoryName: filter.categoryName,
                    enabled: previousCategories[filter.categoryID] ?? filter.enabled,
                    itemCount: filter.itemCount,
                    updatedAt: filter.updatedAt
                )
                try Self.insertCategoryFilterRow(resolved, order: index, in: db)
            }
            return true
        }
    }

    public func setFidEnabled(_ fid: String, enabled: Bool, date: Date = .now) async throws {
        try await write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT manual_order, filter_json FROM favorite_update_fid_filters WHERE fid = ?",
                arguments: [fid]
            ) else {
                return false
            }
            var filter = try Self.decode(FavoriteUpdateFidFilter.self, from: row["filter_json"] as String)
            filter.enabled = enabled
            filter.updatedAt = date
            try Self.insertFidFilterRow(filter, order: row["manual_order"] as Int, in: db)
            return true
        }
    }

    public func setCategoryEnabled(_ categoryID: String, enabled: Bool, date: Date = .now) async throws {
        try await write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT manual_order, filter_json FROM favorite_update_category_filters WHERE category_id = ?",
                arguments: [categoryID]
            ) else {
                return false
            }
            var filter = try Self.decode(FavoriteUpdateCategoryFilter.self, from: row["filter_json"] as String)
            filter.enabled = enabled
            filter.updatedAt = date
            try Self.insertCategoryFilterRow(filter, order: row["manual_order"] as Int, in: db)
            return true
        }
    }

    /// Lets a cascade writer that mutated this store's tables inside its own
    /// GRDB transaction (`MangaDirectoryStore`'s rename) emit the same change
    /// signal the actor's own mutations post.
    public nonisolated func notifyExternalMutation() {
        postChangeNotification()
    }

    /// Runs `updates` in one write transaction and posts the change
    /// notification when the closure reports it actually mutated state.
    private func write(_ updates: @escaping @Sendable (Database) throws -> Bool) async throws {
        let didMutate: Bool
        do {
            didMutate = try await database.write(updates)
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
        if didMutate {
            postChangeNotification()
        }
    }

    private static func state(in db: Database) throws -> FavoriteUpdateStoreState {
        FavoriteUpdateStoreState(
            trackedTargets: try String.fetchAll(
                db,
                sql: "SELECT target_json FROM favorite_update_tracked_targets ORDER BY target_id ASC"
            ).map { try decode(FavoriteUpdateTrackedTarget.self, from: $0) },
            events: try String.fetchAll(
                db,
                sql: "SELECT event_json FROM favorite_update_events ORDER BY detected_at DESC, id DESC"
            ).map { try decode(FavoriteUpdateEvent.self, from: $0) },
            runs: try String.fetchAll(
                db,
                sql: "SELECT run_json FROM favorite_update_runs ORDER BY updated_at DESC, run_id DESC"
            ).map { try decode(FavoriteUpdateRunSnapshot.self, from: $0) },
            fidFilters: try fidFilters(in: db),
            categoryFilters: try categoryFilters(in: db)
        )
    }

    private static func activeEvents(in db: Database) throws -> [FavoriteUpdateEvent] {
        try String.fetchAll(
            db,
            sql: """
            SELECT event_json FROM favorite_update_events
            WHERE dismissed_at IS NULL
            ORDER BY detected_at DESC, id DESC
            """
        ).map { try decode(FavoriteUpdateEvent.self, from: $0) }
    }

    private static func event(id: String, in db: Database) throws -> FavoriteUpdateEvent? {
        guard let json = try String.fetchOne(
            db,
            sql: "SELECT event_json FROM favorite_update_events WHERE id = ?",
            arguments: [id]
        ) else {
            return nil
        }
        return try decode(FavoriteUpdateEvent.self, from: json)
    }

    private static func trackedTarget(id: String, in db: Database) throws -> FavoriteUpdateTrackedTarget? {
        guard let json = try String.fetchOne(
            db,
            sql: "SELECT target_json FROM favorite_update_tracked_targets WHERE target_id = ?",
            arguments: [id]
        ) else {
            return nil
        }
        return try decode(FavoriteUpdateTrackedTarget.self, from: json)
    }

    private static func fidFilters(in db: Database) throws -> [FavoriteUpdateFidFilter] {
        try String.fetchAll(
            db,
            sql: "SELECT filter_json FROM favorite_update_fid_filters ORDER BY manual_order ASC, fid ASC"
        ).map { try decode(FavoriteUpdateFidFilter.self, from: $0) }
    }

    private static func categoryFilters(in db: Database) throws -> [FavoriteUpdateCategoryFilter] {
        try String.fetchAll(
            db,
            sql: "SELECT filter_json FROM favorite_update_category_filters ORDER BY manual_order ASC, category_id ASC"
        ).map { try decode(FavoriteUpdateCategoryFilter.self, from: $0) }
    }

    private static func upsertTrackedTarget(_ target: FavoriteUpdateTrackedTarget, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO favorite_update_tracked_targets (target_id, target_json)
            VALUES (?, ?)
            ON CONFLICT(target_id) DO UPDATE SET target_json = excluded.target_json
            """,
            arguments: [target.id, try encode(target)]
        )
    }

    private static func insertEventRow(_ event: FavoriteUpdateEvent, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO favorite_update_events (id, target_id, detected_at, dismissed_at, event_json)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [
                event.id,
                event.target.id,
                event.detectedAt.timeIntervalSince1970,
                event.dismissedAt?.timeIntervalSince1970,
                try encode(event),
            ]
        )
    }

    private static func insertFidFilterRow(_ filter: FavoriteUpdateFidFilter, order: Int, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO favorite_update_fid_filters (fid, manual_order, filter_json)
            VALUES (?, ?, ?)
            """,
            arguments: [filter.fid, order, try encode(filter)]
        )
    }

    private static func insertCategoryFilterRow(_ filter: FavoriteUpdateCategoryFilter, order: Int, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO favorite_update_category_filters (category_id, manual_order, filter_json)
            VALUES (?, ?, ?)
            """,
            arguments: [filter.categoryID, order, try encode(filter)]
        )
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
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
