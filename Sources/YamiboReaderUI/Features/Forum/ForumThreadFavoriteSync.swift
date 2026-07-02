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
        favoriteStore: (any FavoriteStoring)? = nil,
        localFavoriteLibraryStore: LocalFirstFavoriteLibraryStore? = nil,
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
        if let localFavoriteLibraryStore {
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
        if let favoriteStore {
            return try await upsert(favorite, in: favoriteStore)
        }
        return favorite
    }

    static func removeFavorite(
        _ favorite: Favorite,
        favoriteStore: (any FavoriteStoring)? = nil,
        localFavoriteLibraryStore: LocalFirstFavoriteLibraryStore? = nil,
        readingProgressStore: ReadingProgressStore?,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws {
        if let localFavoriteLibraryStore {
            var document = await localFavoriteLibraryStore.load()
            document.removeItem(target: localTarget(for: favorite))
            try await localFavoriteLibraryStore.save(document)
        }
        if let remoteRepository {
            let remoteFavoriteID = try await remoteFavoriteID(for: favorite, remoteRepository: remoteRepository)
            try await remoteRepository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
        }
        if let favoriteStore {
            _ = try await favoriteStore.deleteFavorite(id: favorite.id)
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

    private static func upsert(_ incoming: Favorite, in favoriteStore: any FavoriteStoring) async throws -> Favorite {
        var favorites = await favoriteStore.loadFavorites()
        if let index = favorites.firstIndex(where: { sameThread($0.url, incoming.url) }) {
            var updated = favorites[index]
            if updated.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.title = incoming.title
            }
            updated.remoteFavoriteID = incoming.remoteFavoriteID ?? updated.remoteFavoriteID
            if updated.authorID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                updated.authorID = incoming.authorID
            }
            if updated.type == .unknown {
                updated.type = incoming.type
            }
            favorites[index] = updated
            try await favoriteStore.saveFavorites(favorites)
            return updated
        }

        try await favoriteStore.saveFavorites(favorites + [incoming])
        return incoming
    }

    private static func sameThread(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsThreadID = threadID(from: lhs),
              let rhsThreadID = threadID(from: rhs) else {
            return lhs == rhs
        }
        return lhsThreadID == rhsThreadID
    }

    private static func threadID(from url: URL) -> String? {
        let resolvedURL = URL(string: url.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL ?? url.absoluteURL
        if let value = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "tid" || $0.name == "ptid" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return MangaTitleCleaner.extractTid(from: resolvedURL.absoluteString)
    }

    @discardableResult
    private static func upsertLocalFirstFavorite(
        _ favorite: Favorite,
        forumID: String?,
        forumName: String?,
        coverURL: URL?,
        contentUpdatedAt: Date?,
        localFavoriteLibraryStore: LocalFirstFavoriteLibraryStore?
    ) async throws -> FavoriteItem {
        guard let localFavoriteLibraryStore else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_library.item_requires_location"))
        }
        var document = await localFavoriteLibraryStore.load()
        let target = localTarget(for: favorite)
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

    private static func localTarget(for favorite: Favorite) -> FavoriteContentTarget {
        let kind: FavoriteContentTargetKind = favorite.type == .novel ? .novelThread : .normalThread
        return FavoriteContentTarget(kind: kind, threadURL: favorite.url)
    }
}

private extension FavoriteItem {
    func favorite(threadURL: URL, type: FavoriteType) -> Favorite {
        Favorite(
            id: id,
            title: title,
            displayName: displayName,
            url: target.canonicalURL ?? threadURL,
            remoteFavoriteID: remoteMapping?.yamiboFavoriteID,
            type: type,
            tagIDs: tagIDs
        )
    }
}
