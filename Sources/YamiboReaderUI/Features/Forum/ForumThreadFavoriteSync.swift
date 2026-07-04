import Foundation
import YamiboReaderCore

protocol ForumThreadFavoriteRemoteOperating: Sendable {
    func addThreadFavorite(threadURL: URL, formHash: String?) async throws -> Favorite?
    func deleteFavorite(remoteFavoriteID: String) async throws
    func remoteFavorite(for threadURL: URL, maxPages: Int) async throws -> Favorite?
}

extension FavoriteRepository: ForumThreadFavoriteRemoteOperating {}

enum ForumThreadFavoriteSync {
    static func addFavorite(
        threadURL: URL,
        title: String,
        type: FavoriteType,
        authorID: String?,
        forumID: String? = nil,
        forumName: String? = nil,
        coverURL: URL? = nil,
        contentUpdatedAt: Date? = nil,
        formHash: String?,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws -> Favorite {
        let remoteFavorite = try await remoteRepository?.addThreadFavorite(threadURL: threadURL, formHash: formHash)
        let favorite = Favorite(
            title: title,
            url: threadURL,
            remoteFavoriteID: remoteFavorite?.remoteFavoriteID,
            authorID: authorID,
            type: type
        )
        let item = try await upsertLocalFirstFavorite(
            favorite,
            forumID: forumID,
            forumName: forumName,
            coverURL: coverURL,
            contentUpdatedAt: contentUpdatedAt,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )
        return item.favorite(threadURL: threadURL, type: type)
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
        if let remoteFavorite = try await remoteRepository.remoteFavorite(for: favorite.url, maxPages: 30),
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
        coverURL: URL?,
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
            coverURL: coverURL,
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
        guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: favorite.url) else {
            throw YamiboError.missingFavoriteThreadID
        }
        return FavoriteContentTarget(kind: kind, threadID: threadID)
    }
}

private extension FavoriteItem {
    func favorite(threadURL: URL, type: FavoriteType) -> Favorite {
        Favorite(
            id: id,
            title: title,
            displayName: displayName,
            url: threadURL,
            remoteFavoriteID: remoteMapping?.yamiboFavoriteID,
            type: type,
            tagIDs: tagIDs
        )
    }
}
