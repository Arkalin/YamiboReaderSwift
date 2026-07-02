import Foundation

public struct FavoriteLibrarySyncMetadata: Codable, Equatable, Sendable {
    public var remoteFavoritesUpdatedAt: Date?
    public var readingPositionUpdatedAtByCanonicalURL: [String: Date]
    public var lastReadAtUpdatedAtByCanonicalURL: [String: Date]
    public var favoriteMetadataUpdatedAtByCanonicalURL: [String: Date]
    public var favoriteOrganizationUpdatedAtByCanonicalURL: [String: Date]
    public var collectionUpdatedAtByID: [String: Date]
    public var tagUpdatedAtByID: [String: Date]

    public init(
        remoteFavoritesUpdatedAt: Date? = nil,
        readingPositionUpdatedAtByCanonicalURL: [String: Date] = [:],
        lastReadAtUpdatedAtByCanonicalURL: [String: Date] = [:],
        favoriteMetadataUpdatedAtByCanonicalURL: [String: Date] = [:],
        favoriteOrganizationUpdatedAtByCanonicalURL: [String: Date] = [:],
        collectionUpdatedAtByID: [String: Date] = [:],
        tagUpdatedAtByID: [String: Date] = [:]
    ) {
        self.remoteFavoritesUpdatedAt = remoteFavoritesUpdatedAt
        self.readingPositionUpdatedAtByCanonicalURL = readingPositionUpdatedAtByCanonicalURL
        self.lastReadAtUpdatedAtByCanonicalURL = lastReadAtUpdatedAtByCanonicalURL
        self.favoriteMetadataUpdatedAtByCanonicalURL = favoriteMetadataUpdatedAtByCanonicalURL
        self.favoriteOrganizationUpdatedAtByCanonicalURL = favoriteOrganizationUpdatedAtByCanonicalURL
        self.collectionUpdatedAtByID = collectionUpdatedAtByID
        self.tagUpdatedAtByID = tagUpdatedAtByID
    }

    public var isEmpty: Bool {
        remoteFavoritesUpdatedAt == nil &&
            readingPositionUpdatedAtByCanonicalURL.isEmpty &&
            lastReadAtUpdatedAtByCanonicalURL.isEmpty &&
            favoriteMetadataUpdatedAtByCanonicalURL.isEmpty &&
            favoriteOrganizationUpdatedAtByCanonicalURL.isEmpty &&
            collectionUpdatedAtByID.isEmpty &&
            tagUpdatedAtByID.isEmpty
    }

    public static func inferred(from snapshot: FavoriteLibrarySnapshot, updatedAt date: Date) -> Self {
        var metadata = Self(remoteFavoritesUpdatedAt: date)
        for key in snapshot.favoriteCanonicalURLKeys {
            metadata.readingPositionUpdatedAtByCanonicalURL[key] = date
            metadata.lastReadAtUpdatedAtByCanonicalURL[key] = date
            metadata.favoriteMetadataUpdatedAtByCanonicalURL[key] = date
            metadata.favoriteOrganizationUpdatedAtByCanonicalURL[key] = date
        }
        for collection in snapshot.collections {
            metadata.collectionUpdatedAtByID[collection.id] = date
        }
        for tag in snapshot.tags {
            metadata.tagUpdatedAtByID[tag.id] = date
        }
        return metadata
    }

    public mutating func inferMissingDomains(from snapshot: FavoriteLibrarySnapshot, updatedAt date: Date) {
        if remoteFavoritesUpdatedAt == nil {
            remoteFavoritesUpdatedAt = date
        }
        for key in snapshot.favoriteCanonicalURLKeys {
            readingPositionUpdatedAtByCanonicalURL[key] = readingPositionUpdatedAtByCanonicalURL[key] ?? date
            lastReadAtUpdatedAtByCanonicalURL[key] = lastReadAtUpdatedAtByCanonicalURL[key] ?? date
            favoriteMetadataUpdatedAtByCanonicalURL[key] = favoriteMetadataUpdatedAtByCanonicalURL[key] ?? date
            favoriteOrganizationUpdatedAtByCanonicalURL[key] = favoriteOrganizationUpdatedAtByCanonicalURL[key] ?? date
        }
        for collection in snapshot.collections {
            collectionUpdatedAtByID[collection.id] = collectionUpdatedAtByID[collection.id] ?? date
        }
        for tag in snapshot.tags {
            tagUpdatedAtByID[tag.id] = tagUpdatedAtByID[tag.id] ?? date
        }
    }
}

public struct FavoriteLibrarySnapshot: Codable, Equatable, Sendable {
    public var favorites: [Favorite]
    public var collections: [FavoriteCollection]
    public var tags: [FavoriteTag]
    public var syncMetadata: FavoriteLibrarySyncMetadata

    private enum CodingKeys: String, CodingKey {
        case favorites
        case collections
        case tags
        case syncMetadata
    }

    public init(
        favorites: [Favorite],
        collections: [FavoriteCollection],
        tags: [FavoriteTag] = [],
        syncMetadata: FavoriteLibrarySyncMetadata = FavoriteLibrarySyncMetadata()
    ) {
        self.favorites = favorites
        self.collections = collections
        self.tags = tags
        self.syncMetadata = syncMetadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([Favorite].self, forKey: .favorites)
        collections = try container.decode([FavoriteCollection].self, forKey: .collections)
        tags = try container.decodeIfPresent([FavoriteTag].self, forKey: .tags) ?? []
        syncMetadata = try container.decodeIfPresent(FavoriteLibrarySyncMetadata.self, forKey: .syncMetadata) ?? FavoriteLibrarySyncMetadata()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(collections, forKey: .collections)
        try container.encode(tags, forKey: .tags)
        if !syncMetadata.isEmpty {
            try container.encode(syncMetadata, forKey: .syncMetadata)
        }
    }

    public var favoriteCanonicalURLKeys: Set<String> {
        Set(favorites.map { FavoriteLibraryURLIdentity.canonicalThreadURLKey(for: $0.url) })
    }
}

public struct FavoriteLibrary: Equatable, Sendable {
    public private(set) var favorites: [Favorite]
    public private(set) var collections: [FavoriteCollection]
    public private(set) var tags: [FavoriteTag]

    public init(snapshot: FavoriteLibrarySnapshot) {
        favorites = snapshot.favorites
        collections = snapshot.collections
        tags = snapshot.tags
    }

    public var snapshot: FavoriteLibrarySnapshot {
        FavoriteLibrarySnapshot(
            favorites: favorites,
            collections: collections,
            tags: tags
        )
    }

    public mutating func setDisplayName(_ displayName: String?, for favoriteID: String) {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
        favorites = favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.displayName = normalized
            return favorite
        }
    }

    public mutating func reconcileRemoteFavorites(_ remoteFavorites: [Favorite]) {
        let localCanonicalURLs = Set(favorites.map { Self.canonicalThreadURL(for: $0) })
        let minRootOrder = min(
            favorites.filter { $0.parentCollectionID == nil }.map(\.manualOrder).min() ?? 0,
            collections.map(\.manualOrder).min() ?? 0
        )

        let unsortedRemoteNewFavorites = remoteFavorites
            .compactMap { remoteFavorite -> Favorite? in
                let canonicalURL = Self.canonicalThreadURL(for: remoteFavorite)
                guard !localCanonicalURLs.contains(canonicalURL) else { return nil }

                var remoteFavorite = remoteFavorite
                remoteFavorite.parentCollectionID = nil
                return remoteFavorite
            }
        let remoteNewFavorites = unsortedRemoteNewFavorites
            .enumerated()
            .map { offset, remoteFavorite in
                var remoteFavorite = remoteFavorite
                if remoteFavorite.parentCollectionID == nil {
                    remoteFavorite.manualOrder = minRootOrder - unsortedRemoteNewFavorites.count + offset
                }
                return remoteFavorite
            }
        var remoteByCanonicalURL: [URL: Favorite] = [:]
        for remoteFavorite in remoteFavorites {
            remoteByCanonicalURL[Self.canonicalThreadURL(for: remoteFavorite)] = remoteFavorite
        }
        favorites = remoteNewFavorites + favorites.map { localFavorite in
            if let remoteFavorite = remoteByCanonicalURL[Self.canonicalThreadURL(for: localFavorite)] {
                var updated = localFavorite
                updated.title = remoteFavorite.title
                updated.url = remoteFavorite.url
                updated.remoteFavoriteID = remoteFavorite.remoteFavoriteID ?? updated.remoteFavoriteID
                if updated.type == .unknown {
                    updated.type = remoteFavorite.type
                }
                return updated
            }

            var localOnly = localFavorite
            localOnly.remoteFavoriteID = nil
            return localOnly
        }
    }

    private static func canonicalThreadURL(for favorite: Favorite) -> URL {
        canonicalThreadURL(from: favorite.url)
    }

    private static func canonicalThreadURL(from url: URL) -> URL {
        FavoriteLibraryURLIdentity.canonicalThreadURL(from: url)
    }

}
