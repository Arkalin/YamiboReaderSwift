import Foundation
import YamiboReaderCore

protocol ForumThreadFavoriteRemoteOperating: Sendable {
    func addThreadFavorite(threadID: String, formHash: String?, resolveRemoteFavorite: Bool) async throws -> Favorite?
    func deleteFavorite(remoteFavoriteID: String) async throws
    func remoteFavorite(forThreadID threadID: String, maxPages: Int) async throws -> Favorite?
}

extension FavoriteRepository: ForumThreadFavoriteRemoteOperating {}

/// Local-first quick actions for single favorites (reader star button, detail
/// pages, favorite item menus).
///
/// Adding writes the local library first and reports the optional Yamibo push
/// separately — a remote failure never rolls the local favorite back. Deleting
/// with `removeRemote` inverts that: the remote delete runs first, so its
/// failure throws and leaves the local item intact (no half-deleted state).
enum FavoriteQuickActions {
    /// Outcome of a Yamibo push attached to an add or single-item sync.
    enum RemotePushResult: Equatable, Sendable {
        case notAttempted
        case synced
        /// Pushed to Yamibo, but the favorite id could not be resolved yet;
        /// the next sync run backfills the mapping.
        case syncedWithoutMapping
        case failed(String)
    }

    struct AddResult: Sendable {
        var favorite: Favorite
        var remote: RemotePushResult
    }

    static func addFavorite(
        threadID: String,
        title: String,
        type: FavoriteType,
        authorID: String?,
        forumID: String? = nil,
        forumName: String? = nil,
        contentUpdatedAt: Date? = nil,
        formHash: String?,
        syncToRemote: Bool,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws -> AddResult {
        let favorite = Favorite(title: title, threadID: threadID, authorID: authorID, type: type)
        let item = try await upsertLocalFirstFavorite(
            favorite,
            forumID: forumID,
            forumName: forumName,
            contentUpdatedAt: contentUpdatedAt,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )
        guard syncToRemote, let remoteRepository else {
            return AddResult(favorite: item.favorite(type: type), remote: .notAttempted)
        }
        do {
            let remoteFavorite = try await remoteRepository.addThreadFavorite(
                threadID: threadID,
                formHash: formHash,
                resolveRemoteFavorite: true
            )
            guard let remoteFavoriteID = normalizedRemoteFavoriteID(remoteFavorite?.remoteFavoriteID) else {
                return AddResult(favorite: item.favorite(type: type), remote: .syncedWithoutMapping)
            }
            var document = await localFavoriteLibraryStore.load()
            document.updateRemoteMapping(for: item.target, yamiboFavoriteID: remoteFavoriteID, yamiboRemoteOrder: nil)
            try await localFavoriteLibraryStore.save(document)
            var synced = item
            synced.remoteMapping = FavoriteRemoteMapping(yamiboFavoriteID: remoteFavoriteID, lastSeenAt: .now)
            return AddResult(favorite: synced.favorite(type: type), remote: .synced)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return AddResult(favorite: item.favorite(type: type), remote: .failed(message))
        }
    }

    /// With `removeRemote`, an unmapped favorite gets one remote lookup;
    /// finding nothing just means there is nothing to delete on the website.
    static func removeFavorite(
        _ favorite: Favorite,
        removeRemote: Bool,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws {
        if removeRemote, let remoteRepository {
            if let remoteFavoriteID = normalizedRemoteFavoriteID(favorite.remoteFavoriteID) {
                try await remoteRepository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
            } else if let remoteFavorite = try await remoteRepository.remoteFavorite(forThreadID: favorite.threadID, maxPages: 30),
                      let remoteFavoriteID = normalizedRemoteFavoriteID(remoteFavorite.remoteFavoriteID) {
                try await remoteRepository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
            }
        }
        var document = await localFavoriteLibraryStore.load()
        document.removeItem(target: try localTarget(for: favorite))
        try await localFavoriteLibraryStore.save(document)
    }

    /// Pushes one existing favorite item to Yamibo (favorites item menu's
    /// "sync to Yamibo" action).
    static func syncFavoriteItemToRemote(
        _ item: FavoriteItem,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        remoteRepository: any ForumThreadFavoriteRemoteOperating
    ) async throws -> RemotePushResult {
        guard let threadID = item.target.threadID else {
            throw YamiboError.missingFavoriteThreadID
        }
        if normalizedRemoteFavoriteID(item.remoteMapping?.yamiboFavoriteID) != nil {
            return .synced
        }
        let remoteFavorite = try await remoteRepository.addThreadFavorite(
            threadID: threadID,
            formHash: nil,
            resolveRemoteFavorite: true
        )
        guard let remoteFavoriteID = normalizedRemoteFavoriteID(remoteFavorite?.remoteFavoriteID) else {
            return .syncedWithoutMapping
        }
        var document = await localFavoriteLibraryStore.load()
        document.updateRemoteMapping(for: item.target, yamiboFavoriteID: remoteFavoriteID, yamiboRemoteOrder: nil)
        try await localFavoriteLibraryStore.save(document)
        return .synced
    }

    // MARK: - Helpers

    @discardableResult
    private static func upsertLocalFirstFavorite(
        _ favorite: Favorite,
        forumID: String?,
        forumName: String?,
        contentUpdatedAt: Date?,
        localFavoriteLibraryStore: FavoriteLibraryStore
    ) async throws -> FavoriteItem {
        var document = await localFavoriteLibraryStore.load()
        let target = try localTarget(for: favorite)
        let item = try FavoriteItem(
            target: target,
            title: favorite.title,
            displayName: favorite.displayName,
            forumID: forumID,
            forumName: forumName,
            contentUpdatedAt: contentUpdatedAt,
            locations: [.category(document.defaultCategory.id)],
            tagIDs: favorite.tagIDs,
            createdAt: .now,
            updatedAt: .now
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        return item
    }

    private static func localTarget(for favorite: Favorite) throws -> FavoriteContentTarget {
        let kind: FavoriteContentTargetKind = favorite.type == .novel ? .novelThread : .normalThread
        return FavoriteContentTarget(kind: kind, threadID: favorite.threadID)
    }

    private static func normalizedRemoteFavoriteID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Pending "also delete from Yamibo?" question raised by a remove action.
struct FavoriteRemovePrompt: Identifiable, Equatable, Sendable {
    let favorite: Favorite
    var id: String { favorite.threadID }
}

extension FavoriteQuickActions.RemotePushResult {
    /// Snackbar copy for the three-state add feedback.
    var addFeedbackMessage: String {
        switch self {
        case .notAttempted:
            L10n.string("favorites.quick.added_local")
        case .synced:
            L10n.string("favorites.quick.added_synced")
        case .syncedWithoutMapping:
            L10n.string("favorites.quick.added_synced_pending")
        case let .failed(reason):
            L10n.string("favorites.quick.added_sync_failed", reason)
        }
    }
}

/// Whether adding this favorite should ask about (or silently perform) the
/// Yamibo push, resolved from the user's remembered choice.
enum FavoriteAddSyncDecision: Equatable, Sendable {
    case prompt
    case silent(syncToRemote: Bool)

    static func resolve(settings: FavoriteLibrarySettings, canSyncRemote: Bool) -> FavoriteAddSyncDecision {
        guard canSyncRemote else { return .silent(syncToRemote: false) }
        return settings.addSyncPromptEnabled ? .prompt : .silent(syncToRemote: settings.addSyncDefault)
    }
}

/// Same resolution for the delete flow's "also remove from Yamibo" question.
enum FavoriteRemoveRemoteDecision: Equatable, Sendable {
    case prompt
    case silent(removeRemote: Bool)

    static func resolve(settings: FavoriteLibrarySettings, canRemoveRemote: Bool) -> FavoriteRemoveRemoteDecision {
        guard canRemoveRemote else { return .silent(removeRemote: false) }
        return settings.removeRemotePromptEnabled ? .prompt : .silent(removeRemote: settings.removeRemoteDefault)
    }
}

private extension FavoriteItem {
    func favorite(type: FavoriteType) -> Favorite {
        guard let threadID = target.threadID else {
            preconditionFailure("Thread favorite conversion requires thread target")
        }
        return Favorite(
            id: id,
            title: title,
            displayName: displayName,
            threadID: threadID,
            remoteFavoriteID: remoteMapping?.yamiboFavoriteID,
            type: type,
            tagIDs: tagIDs
        )
    }
}
