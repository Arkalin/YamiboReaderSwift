import Foundation
import YamiboReaderCore

protocol ForumThreadFavoriteRemoteOperating: Sendable {
    func addThreadFavorite(threadID: String, formHash: String?) async throws -> Favorite?
    func deleteFavorite(remoteFavoriteID: String) async throws
    func remoteFavorite(forThreadID threadID: String, maxPages: Int) async throws -> Favorite?
}

extension FavoriteRepository: ForumThreadFavoriteRemoteOperating {}

enum ForumThreadFavoriteSync {
    static func addFavorite(
        threadID: String,
        title: String,
        type: FavoriteType,
        authorID: String?,
        forumID: String? = nil,
        forumName: String? = nil,
        contentUpdatedAt: Date? = nil,
        formHash: String?,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws -> Favorite {
        let remoteFavorite = try await remoteRepository?.addThreadFavorite(threadID: threadID, formHash: formHash)
        let favorite = Favorite(
            title: title,
            threadID: threadID,
            remoteFavoriteID: remoteFavorite?.remoteFavoriteID,
            authorID: authorID,
            type: type
        )
        let item = try await upsertLocalFirstFavorite(
            favorite,
            forumID: forumID,
            forumName: forumName,
            contentUpdatedAt: contentUpdatedAt,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )
        return item.favorite(type: type)
    }

    static func removeFavorite(
        _ favorite: Favorite,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        readingProgressStore: ReadingProgressStore?,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws {
        var document = await localFavoriteLibraryStore.load()
        document.removeItem(target: try localTarget(for: favorite))
        try await localFavoriteLibraryStore.save(document)
        if let remoteRepository {
            let remoteFavoriteID = try await remoteFavoriteID(for: favorite, remoteRepository: remoteRepository)
            try await remoteRepository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
        }
    }

    private static func remoteFavoriteID(
        for favorite: Favorite,
        remoteRepository: any ForumThreadFavoriteRemoteOperating
    ) async throws -> String {
        if let remoteFavoriteID = favorite.remoteFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteFavoriteID.isEmpty {
            return remoteFavoriteID
        }
        if let remoteFavorite = try await remoteRepository.remoteFavorite(forThreadID: favorite.threadID, maxPages: 30),
           let remoteFavoriteID = remoteFavorite.remoteFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteFavoriteID.isEmpty {
            return remoteFavoriteID
        }
        throw YamiboError.missingFavoriteDeleteID
    }

    @discardableResult
    private static func upsertLocalFirstFavorite(
        _ favorite: Favorite,
        forumID: String?,
        forumName: String?,
        contentUpdatedAt: Date?,
        localFavoriteLibraryStore: FavoriteLibraryStore?
    ) async throws -> FavoriteItem {
        guard let localFavoriteLibraryStore else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_library.item_requires_location"))
        }
        var document = await localFavoriteLibraryStore.load()
        let target = try localTarget(for: favorite)
        let item = try FavoriteItem(
            target: target,
            title: favorite.title,
            displayName: favorite.displayName,
            forumID: forumID,
            forumName: forumName,
            contentUpdatedAt: contentUpdatedAt,
            remoteMapping: favorite.remoteFavoriteID.map {
                FavoriteRemoteMapping(yamiboFavoriteID: $0, lastSeenAt: .now)
            },
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
