import Foundation

public struct YamiboRemoteFavoriteEntry: Hashable, Sendable {
    public var remoteFavoriteID: String
    public var threadID: String
    public var title: String?
    public var remoteOrder: Int

    public init(remoteFavoriteID: String, threadID: String, title: String? = nil, remoteOrder: Int = 0) {
        self.remoteFavoriteID = remoteFavoriteID
        self.threadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title
        self.remoteOrder = remoteOrder
    }
}

/// One page of the Yamibo remote favorite list.
public struct FavoriteYamiboRemotePage: Sendable {
    public var entries: [YamiboRemoteFavoriteEntry]
    public var currentPage: Int
    public var totalPages: Int

    public init(entries: [YamiboRemoteFavoriteEntry], currentPage: Int, totalPages: Int) {
        self.entries = entries
        self.currentPage = max(1, currentPage)
        self.totalPages = max(1, totalPages)
    }
}

/// Network operations the sync engine needs, injected as closures so the UI
/// layer can compose them from its repositories and tests can fake them.
public struct FavoriteYamiboSyncClient: Sendable {
    /// Fetches one page of the remote favorite list.
    public var fetchPage: @Sendable (_ page: Int) async throws -> FavoriteYamiboRemotePage
    /// Resolves a remote entry's thread into a favorite target with metadata
    /// (the entry carries the remote title as a resolution hint).
    /// Implementations are expected to record covers as a side effect.
    public var probe: @Sendable (_ entry: YamiboRemoteFavoriteEntry) async throws -> FavoriteThreadProbeResult
    /// Adds one thread to the Yamibo remote favorites.
    public var addFavorite: @Sendable (_ threadID: String) async throws -> Void

    public init(
        fetchPage: @escaping @Sendable (_ page: Int) async throws -> FavoriteYamiboRemotePage,
        probe: @escaping @Sendable (_ entry: YamiboRemoteFavoriteEntry) async throws -> FavoriteThreadProbeResult,
        addFavorite: @escaping @Sendable (_ threadID: String) async throws -> Void
    ) {
        self.fetchPage = fetchPage
        self.probe = probe
        self.addFavorite = addFavorite
    }
}

/// Five-phase Yamibo favorite sync engine (Android-parity semantics):
///
/// 1. preparing — validate the target category.
/// 2. fetching — page through the remote favorite list.
/// 3. importing — import remote-only threads; existing unmapped items gain the
///    target category location; already-mapped items only refresh the mapping.
/// 4. uploading — push every thread item of the target category that the
///    remote list lacks, including items the website side deleted: the local
///    library is the source of truth and sync converges to the union.
/// 5. reconciling — if anything uploaded, re-fetch the remote list and backfill
///    favorite IDs and ordering.
///
/// Sync never deletes on either side; deletions propagate only through the
/// explicit delete actions. Cancellation is cooperative: the engine finishes
/// the current network call, persists partial progress, and records the run as
/// interrupted.
public struct FavoriteYamiboSyncEngine: Sendable {
    private let libraryStore: FavoriteLibraryStore
    private let client: FavoriteYamiboSyncClient

    public init(libraryStore: FavoriteLibraryStore, client: FavoriteYamiboSyncClient) {
        self.libraryStore = libraryStore
        self.client = client
    }

    /// Runs the five phases starting from `initial` (typically phase .queued).
    /// Every snapshot mutation is pushed through `persist`; the returned
    /// snapshot is terminal (completed, failed, or interrupted).
    public func run(
        snapshot initial: FavoriteRemoteSyncSnapshot,
        directories: [MangaDirectory] = [],
        interruptionReason: @escaping @Sendable () -> FavoriteRemoteSyncWarning? = { nil },
        persist: @escaping @Sendable (FavoriteRemoteSyncSnapshot) async -> Void
    ) async -> FavoriteRemoteSyncSnapshot {
        var snapshot = initial
        var pendingOperations: [@Sendable (inout FavoriteLibraryDocument) -> Void] = []

        func commit(_ mutate: (inout FavoriteRemoteSyncSnapshot) -> Void) async {
            mutate(&snapshot)
            snapshot.updatedAt = .now
            await persist(snapshot)
        }

        /// Records a mutation against `workingDocument` and queues it for replay
        /// onto a freshly-loaded document at save time, so a save never blindly
        /// overwrites edits the user made elsewhere while this run was fetching.
        func record(_ operation: @escaping @Sendable (inout FavoriteLibraryDocument) -> Void) {
            pendingOperations.append(operation)
        }

        /// Reloads the current on-disk document, replays every mutation this run
        /// has queued since the last save, and persists the merged result — this
        /// is what keeps a long-running sync from clobbering concurrent local
        /// edits (deletes, moves, tag changes) with a stale in-memory snapshot.
        func saveDocumentIfDirty() async throws -> FavoriteLibraryDocument? {
            guard !pendingOperations.isEmpty else { return nil }
            let operations = pendingOperations
            let libraryStore = libraryStore
            // Unstructured task: interruption persists partial progress from
            // the cancelled task, and GRDB's async accesses honor Task
            // cancellation — the write must not inherit it.
            let merged = try await Task { () -> FavoriteLibraryDocument in
                var fresh = await libraryStore.load()
                for operation in operations {
                    operation(&fresh)
                }
                try await libraryStore.save(fresh)
                return fresh
            }.value
            pendingOperations.removeAll()
            return merged
        }

        do {
            // Phase 1: preparing
            try Task.checkCancellation()
            await commit { $0.phase = .preparing }
            var workingDocument = await libraryStore.load()
            guard workingDocument.categories.contains(where: { $0.id == snapshot.targetCategoryID }) else {
                throw YamiboError.persistenceFailed(L10n.string("favorites.sync.error.category_missing"))
            }
            let targetLocation = FavoriteLocation.category(snapshot.targetCategoryID)

            // Phase 2: fetching
            await commit { $0.phase = .fetching }
            var remoteEntries: [YamiboRemoteFavoriteEntry] = []
            var remoteThreadIDs: Set<String> = []
            var reportedPageCountChange = false
            var page = 1
            var totalPages: Int?
            while true {
                try Task.checkCancellation()
                let result: FavoriteYamiboRemotePage
                do {
                    result = try await client.fetchPage(page)
                } catch let error where page == 1 && Self.isEmptyRemoteFavoritesError(error) {
                    // An empty first page (HTML parsed fine, zero entries, no
                    // auth/flood markers) means the account genuinely has no
                    // remote favorites yet — a valid state, not a failure.
                    // Sync must still proceed to the upload phase.
                    result = FavoriteYamiboRemotePage(entries: [], currentPage: 1, totalPages: 1)
                }
                if let known = totalPages, known != result.totalPages, !reportedPageCountChange {
                    reportedPageCountChange = true
                    await commit { $0.warnings.append(.remotePageCountChanged) }
                }
                totalPages = result.totalPages
                var duplicateTitles: [String] = []
                for entry in result.entries {
                    guard remoteThreadIDs.insert(entry.threadID).inserted else {
                        duplicateTitles.append(Self.postLabel(threadID: entry.threadID, title: entry.title))
                        continue
                    }
                    var ordered = entry
                    ordered.remoteOrder = remoteEntries.count
                    remoteEntries.append(ordered)
                }
                let accumulated = remoteEntries.count
                let resolvedTotal = totalPages ?? page
                await commit { snapshot in
                    snapshot.currentPage = page
                    snapshot.totalPages = resolvedTotal
                    snapshot.scannedCount = accumulated
                    snapshot.logEntries.append(.fetchedPage(page: page, totalPages: resolvedTotal, accumulatedCount: accumulated))
                    for title in duplicateTitles {
                        snapshot.warnings.append(.duplicateRemoteEntry(title: title))
                    }
                }
                if page >= resolvedTotal || result.entries.isEmpty {
                    break
                }
                page += 1
            }

            // Phase 3: importing
            await commit { $0.phase = .importing }
            var skippedPathCounts: [(path: String, count: Int)] = []
            let importTotal = remoteEntries.count
            for (offset, entry) in remoteEntries.enumerated() {
                try Task.checkCancellation()
                let label = Self.postLabel(threadID: entry.threadID, title: entry.title)
                await commit { $0.logEntries.append(.importingItem(index: offset + 1, total: importTotal, title: label)) }

                if let existing = workingDocument.items.first(where: { $0.target.threadID == entry.threadID }) {
                    let alreadyMapped = existing.remoteMapping?.yamiboFavoriteID != nil
                    let existingTarget = existing.target
                    if !alreadyMapped {
                        workingDocument.addLocation(targetLocation, to: existingTarget)
                        record { doc in doc.addLocation(targetLocation, to: existingTarget) }
                    }
                    workingDocument.updateRemoteMapping(
                        for: existingTarget,
                        yamiboFavoriteID: entry.remoteFavoriteID,
                        yamiboRemoteOrder: entry.remoteOrder
                    )
                    record { doc in
                        doc.updateRemoteMapping(
                            for: existingTarget,
                            yamiboFavoriteID: entry.remoteFavoriteID,
                            yamiboRemoteOrder: entry.remoteOrder
                        )
                    }
                    if alreadyMapped {
                        let path = Self.pathDescription(for: existing, in: workingDocument)
                        if let index = skippedPathCounts.firstIndex(where: { $0.path == path }) {
                            skippedPathCounts[index].count += 1
                        } else {
                            skippedPathCounts.append((path, 1))
                        }
                        await commit { $0.skippedCount += 1 }
                    } else {
                        await commit { $0.importedCount += 1 }
                    }
                    continue
                }

                do {
                    let probeResult = try await Self.probeWithRetry(entry, client: client)
                    let mapping = FavoriteRemoteMapping(
                        yamiboFavoriteID: entry.remoteFavoriteID,
                        yamiboRemoteOrder: entry.remoteOrder,
                        lastSeenAt: .now
                    )
                    if case let .mangaTitle(_, cleanBookName) = probeResult.target {
                        let chapterTitle = entry.title ?? probeResult.title
                        _ = try workingDocument.importMangaChapterFavorite(
                            chapterTID: entry.threadID,
                            chapterTitle: chapterTitle,
                            directories: directories,
                            fallbackCleanBookName: cleanBookName,
                            location: targetLocation,
                            remoteMapping: mapping
                        )
                        record { doc in
                            do {
                                _ = try doc.importMangaChapterFavorite(
                                    chapterTID: entry.threadID,
                                    chapterTitle: chapterTitle,
                                    directories: directories,
                                    fallbackCleanBookName: cleanBookName,
                                    location: targetLocation,
                                    remoteMapping: mapping
                                )
                            } catch {
                                YamiboLog.sync.error("Failed to replay manga chapter favorite import for thread \(entry.threadID, privacy: .public) onto reloaded document: \(error)")
                            }
                        }
                    } else {
                        _ = try workingDocument.importThreadFavorite(
                            probeResult: probeResult,
                            location: targetLocation,
                            remoteMapping: mapping
                        )
                        record { doc in
                            do {
                                _ = try doc.importThreadFavorite(
                                    probeResult: probeResult,
                                    location: targetLocation,
                                    remoteMapping: mapping
                                )
                            } catch {
                                YamiboLog.sync.error("Failed to replay thread favorite import for thread \(entry.threadID, privacy: .public) onto reloaded document: \(error)")
                            }
                        }
                    }
                    await commit { $0.importedCount += 1 }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error where Self.isRunFatal(error) {
                    throw error
                } catch {
                    let reason = Self.truncatedReason(from: error)
                    await commit { snapshot in
                        snapshot.failedCount += 1
                        snapshot.warnings.append(.importFailedItem(title: label, reason: reason))
                    }
                }
            }
            await commit { snapshot in
                for entry in skippedPathCounts {
                    snapshot.logEntries.append(.skippedSyncedItems(path: entry.path, count: entry.count))
                }
            }
            if let merged = try await saveDocumentIfDirty() {
                workingDocument = merged
            }

            // Phase 4: uploading
            let uploadCandidates = workingDocument.items.filter { item in
                item.locations.contains { $0.categoryID == snapshot.targetCategoryID }
                    && item.target.threadID.map { !remoteThreadIDs.contains($0) } == true
            }
            await commit { snapshot in
                snapshot.phase = .uploading
                snapshot.uploadTargetCount = uploadCandidates.count
                snapshot.logEntries.append(.uploading(targetCount: uploadCandidates.count))
            }
            for (offset, item) in uploadCandidates.enumerated() {
                try Task.checkCancellation()
                guard let threadID = item.target.threadID else { continue }
                let label = Self.postLabel(threadID: threadID, title: item.resolvedDisplayTitle)
                do {
                    try await client.addFavorite(threadID)
                    await commit { snapshot in
                        snapshot.uploadedCount += 1
                        snapshot.logEntries.append(.uploadedItem(index: offset + 1, total: uploadCandidates.count, title: label))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error where Self.isRunFatal(error) {
                    throw error
                } catch {
                    let reason = Self.truncatedReason(from: error)
                    await commit { snapshot in
                        snapshot.failedCount += 1
                        snapshot.warnings.append(.uploadFailedItem(title: label, reason: reason))
                    }
                }
            }

            // Phase 5: reconciling
            if snapshot.uploadedCount > 0 {
                await commit { snapshot in
                    snapshot.phase = .reconciling
                    snapshot.logEntries.append(.reconciling)
                }
                do {
                    let allEntries = try await Self.fetchAllPages(client: client)
                    for entry in allEntries {
                        guard let target = workingDocument.items.first(where: { $0.target.threadID == entry.threadID })?.target else {
                            continue
                        }
                        workingDocument.updateRemoteMapping(
                            for: target,
                            yamiboFavoriteID: entry.remoteFavoriteID,
                            yamiboRemoteOrder: entry.remoteOrder
                        )
                        record { doc in
                            doc.updateRemoteMapping(
                                for: target,
                                yamiboFavoriteID: entry.remoteFavoriteID,
                                yamiboRemoteOrder: entry.remoteOrder
                            )
                        }
                    }
                    if let merged = try await saveDocumentIfDirty() {
                        workingDocument = merged
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let reason = Self.truncatedReason(from: error)
                    await commit { $0.warnings.append(.reconcileFailed(reason: reason)) }
                }
            }

            let importedCount = snapshot.importedCount
            let uploadedCount = snapshot.uploadedCount
            await commit { snapshot in
                snapshot.status = .completed
                snapshot.phase = .completed
                snapshot.finishedAt = .now
                snapshot.logEntries.append(.completed(importedCount: importedCount, uploadedCount: uploadedCount))
            }
        } catch let error where error.isTaskCancellation {
            do {
                _ = try await saveDocumentIfDirty()
            } catch let saveError {
                YamiboLog.sync.error("Failed to save queued favorite sync mutations after cancellation: \(saveError)")
            }
            let reason = interruptionReason() ?? .interrupted
            await commit { snapshot in
                snapshot.status = .interrupted
                snapshot.phase = .interrupted
                snapshot.finishedAt = .now
                snapshot.warnings.append(reason)
                snapshot.logEntries.append(.interrupted)
            }
        } catch {
            do {
                _ = try await saveDocumentIfDirty()
            } catch let saveError {
                YamiboLog.sync.error("Failed to save queued favorite sync mutations after run failure: \(saveError)")
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await commit { snapshot in
                snapshot.status = .failed
                snapshot.phase = .failed
                snapshot.finishedAt = .now
                snapshot.errorMessages.append(message)
                snapshot.logEntries.append(.failed)
            }
        }
        return snapshot
    }

    // MARK: - Helpers

    private static func probeWithRetry(
        _ entry: YamiboRemoteFavoriteEntry,
        client: FavoriteYamiboSyncClient,
        attempts: Int = 3
    ) async throws -> FavoriteThreadProbeResult {
        var lastError: any Error = YamiboError.parsingFailed(context: entry.threadID)
        for attempt in 1 ... max(1, attempts) {
            do {
                return try await client.probe(entry)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error where isRunFatal(error) {
                throw error
            } catch {
                lastError = error
                if attempt < attempts {
                    try Task.checkCancellation()
                }
            }
        }
        throw lastError
    }

    private static func fetchAllPages(client: FavoriteYamiboSyncClient) async throws -> [YamiboRemoteFavoriteEntry] {
        var entries: [YamiboRemoteFavoriteEntry] = []
        var seenThreadIDs: Set<String> = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let result = try await client.fetchPage(page)
            for entry in result.entries where seenThreadIDs.insert(entry.threadID).inserted {
                var ordered = entry
                ordered.remoteOrder = entries.count
                entries.append(ordered)
            }
            if page >= result.totalPages || result.entries.isEmpty {
                return entries
            }
            page += 1
        }
    }

    /// Errors that abort the whole run instead of failing one item, matching
    /// the Android reference (not logged in / site maintenance).
    private static func isRunFatal(_ error: any Error) -> Bool {
        guard let yamiboError = error as? YamiboError else { return false }
        switch yamiboError {
        case .notAuthenticated, .floodControl, .missingFavoriteAddToken:
            return true
        default:
            return false
        }
    }

    /// True only for the specific "HTML parsed but zero favorite entries"
    /// failure mode — not for auth/flood-control errors, which must still
    /// abort the run.
    private static func isEmptyRemoteFavoritesError(_ error: any Error) -> Bool {
        guard let yamiboError = error as? YamiboError else { return false }
        if case .parsingFailed = yamiboError { return true }
        return false
    }

    private static func postLabel(threadID: String, title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "#\(threadID)" : "#\(threadID) \(trimmed)"
    }

    /// Primary organization path of an item, for the "already synced at" log.
    private static func pathDescription(for item: FavoriteItem, in document: FavoriteLibraryDocument) -> String {
        guard let location = item.locations.first else { return "" }
        let categoryName = document.categories.first { $0.id == location.categoryID }?.displayName ?? location.categoryID
        guard let collectionID = location.collectionID else { return categoryName }
        let collectionName = document.collections.first { $0.id == collectionID }?.name ?? collectionID
        return "\(categoryName)/\(collectionName)"
    }

    private static func truncatedReason(from error: any Error, maxCharacters: Int = 100) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let normalized = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > maxCharacters else { return normalized }
        return String(normalized.prefix(maxCharacters)) + "…"
    }
}

/// Shared cancellation detection for favorite background sessions.
public extension Error {
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
