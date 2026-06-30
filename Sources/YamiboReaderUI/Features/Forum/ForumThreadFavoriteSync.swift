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
        formHash: String?,
        favoriteStore: any FavoriteStoring,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws -> Favorite {
        let remoteFavorite = try await remoteRepository?.addThreadFavorite(threadURL: threadURL, formHash: formHash)
        let favorite = Favorite(
            title: title,
            url: threadURL,
            remoteFavoriteID: remoteFavorite?.remoteFavoriteID,
            authorID: authorID,
            isHidden: false,
            type: type
        )
        return try await upsert(favorite, in: favoriteStore)
    }

    static func removeFavorite(
        _ favorite: Favorite,
        favoriteStore: any FavoriteStoring,
        readingProgressStore: ReadingProgressStore?,
        remoteRepository: (any ForumThreadFavoriteRemoteOperating)?
    ) async throws {
        if let remoteRepository {
            let remoteFavoriteID = try await remoteFavoriteID(for: favorite, remoteRepository: remoteRepository)
            try await remoteRepository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
        }
        _ = try await readingProgressStore?.saveFavoriteLegacyProgress(favorite)
        _ = try await favoriteStore.deleteFavorite(id: favorite.id)
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
}
