import Foundation
import YamiboReaderCore

/// Deletes the Yamibo remote counterparts of local favorites when the user
/// removes items "everywhere". Falls back to a remote favorite-list lookup
/// when the stored remote mapping has no usable favorite ID.
@MainActor
struct YamiboRemoteFavoriteDeleter {
    let makeFavoriteRepository: @Sendable () async -> FavoriteRepository

    /// Test seam: replaces the whole remote deletion flow when set.
    var overrideHandler: (([FavoriteItem]) async throws -> Void)?

    func deleteRemoteFavorites(for items: [FavoriteItem]) async throws {
        if let overrideHandler {
            try await overrideHandler(items)
            return
        }
        let remoteItems = items.filter { item in
            if let remoteFavoriteID = item.remoteMapping?.yamiboFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !remoteFavoriteID.isEmpty {
                return true
            }
            return item.remoteMapping != nil && item.target.threadID != nil
        }
        guard !remoteItems.isEmpty else { return }
        let repository = await makeFavoriteRepository()
        for item in remoteItems {
            do {
                let remoteFavoriteID = try await remoteFavoriteID(for: item, repository: repository)
                try await repository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
            } catch YamiboError.missingFavoriteDeleteID {
                // The remote favorite is already gone (deleted on the website,
                // or the mapping never resolved) — nothing to delete remotely,
                // but the local removal this call is part of must still proceed.
                continue
            }
        }
    }

    private func remoteFavoriteID(for item: FavoriteItem, repository: FavoriteRepository) async throws -> String {
        if let remoteFavoriteID = item.remoteMapping?.yamiboFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteFavoriteID.isEmpty {
            return remoteFavoriteID
        }
        guard let threadID = item.target.threadID else {
            throw YamiboError.missingFavoriteDeleteID
        }
        if let remoteFavorite = try await repository.remoteFavorite(forThreadID: threadID, maxPages: 30),
           let remoteFavoriteID = remoteFavorite.remoteFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteFavoriteID.isEmpty {
            return remoteFavoriteID
        }
        throw YamiboError.missingFavoriteDeleteID
    }
}
