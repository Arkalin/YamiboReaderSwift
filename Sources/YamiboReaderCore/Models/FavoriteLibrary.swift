import Foundation

public struct FavoriteLibrarySnapshot: Codable, Equatable, Sendable {
    public var favorites: [Favorite]
    public var collections: [FavoriteCollection]
    public var archivedMetadata: [FavoriteMetadataArchiveEntry]

    private enum CodingKeys: String, CodingKey {
        case favorites
        case collections
        case archivedMetadata
    }

    public init(
        favorites: [Favorite],
        collections: [FavoriteCollection],
        archivedMetadata: [FavoriteMetadataArchiveEntry] = []
    ) {
        self.favorites = favorites
        self.collections = collections
        self.archivedMetadata = archivedMetadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([Favorite].self, forKey: .favorites)
        collections = try container.decode([FavoriteCollection].self, forKey: .collections)
        archivedMetadata = try container.decodeIfPresent([FavoriteMetadataArchiveEntry].self, forKey: .archivedMetadata) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(collections, forKey: .collections)
        try container.encode(archivedMetadata, forKey: .archivedMetadata)
    }
}

public struct FavoriteMetadataArchiveEntry: Codable, Equatable, Sendable {
    public var canonicalThreadURL: URL
    public var displayName: String?
    public var lastPage: Int
    public var lastView: Int
    public var lastChapter: String?
    public var authorID: String?
    public var novelResumePoint: ReaderResumePoint?
    public var isHidden: Bool
    public var type: FavoriteType
    public var lastMangaURL: URL?
    public var parentCollectionID: String?
    public var manualOrder: Int
    public var lastReadAt: Date?

    public init(
        canonicalThreadURL: URL,
        displayName: String?,
        lastPage: Int,
        lastView: Int,
        lastChapter: String?,
        authorID: String?,
        novelResumePoint: ReaderResumePoint?,
        isHidden: Bool,
        type: FavoriteType,
        lastMangaURL: URL?,
        parentCollectionID: String?,
        manualOrder: Int,
        lastReadAt: Date?
    ) {
        self.canonicalThreadURL = canonicalThreadURL
        self.displayName = displayName
        self.lastPage = max(0, lastPage)
        self.lastView = max(1, lastView)
        self.lastChapter = lastChapter
        self.authorID = authorID
        self.novelResumePoint = novelResumePoint
        self.isHidden = isHidden
        self.type = type
        self.lastMangaURL = lastMangaURL
        self.parentCollectionID = parentCollectionID
        self.manualOrder = manualOrder
        self.lastReadAt = lastReadAt
    }

    public init(favorite: Favorite) {
        self.init(
            canonicalThreadURL: ReaderCacheIdentity.canonicalThreadURL(from: favorite.url),
            displayName: favorite.displayName,
            lastPage: favorite.lastPage,
            lastView: favorite.lastView,
            lastChapter: favorite.lastChapter,
            authorID: favorite.authorID,
            novelResumePoint: favorite.novelResumePoint,
            isHidden: favorite.isHidden,
            type: favorite.type,
            lastMangaURL: favorite.lastMangaURL,
            parentCollectionID: favorite.parentCollectionID,
            manualOrder: favorite.manualOrder,
            lastReadAt: favorite.lastReadAt
        )
    }
}

public struct FavoriteLibrary: Equatable, Sendable {
    public private(set) var favorites: [Favorite]
    public private(set) var collections: [FavoriteCollection]
    public private(set) var archivedMetadata: [FavoriteMetadataArchiveEntry]

    public init(snapshot: FavoriteLibrarySnapshot) {
        favorites = snapshot.favorites
        collections = snapshot.collections
        archivedMetadata = snapshot.archivedMetadata
    }

    public var snapshot: FavoriteLibrarySnapshot {
        FavoriteLibrarySnapshot(
            favorites: favorites,
            collections: collections,
            archivedMetadata: archivedMetadata
        )
    }

    public mutating func reconcileRemoteFavorites(_ remoteFavorites: [Favorite]) {
        let validCollectionIDs = Set(collections.map(\.id))
        let localCanonicalURLs = Set(favorites.map { Self.canonicalThreadURL(for: $0) })
        let minRootOrder = min(
            favorites.filter { $0.parentCollectionID == nil }.map(\.manualOrder).min() ?? 0,
            collections.map(\.manualOrder).min() ?? 0
        )
        let archiveByURL = Dictionary(uniqueKeysWithValues: archivedMetadata.map { ($0.canonicalThreadURL, $0) })
        var restoredArchiveURLs = Set<URL>()

        let unsortedRemoteNewFavorites = remoteFavorites
            .compactMap { remoteFavorite -> Favorite? in
                let canonicalURL = Self.canonicalThreadURL(for: remoteFavorite)
                guard !localCanonicalURLs.contains(canonicalURL) else { return nil }

                var remoteFavorite = remoteFavorite
                remoteFavorite.parentCollectionID = nil
                if let archive = archiveByURL[canonicalURL] {
                    remoteFavorite.applyArchivedMetadata(archive, validCollectionIDs: validCollectionIDs)
                    restoredArchiveURLs.insert(archive.canonicalThreadURL)
                }
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
        let remoteByCanonicalURL = Dictionary(uniqueKeysWithValues: remoteFavorites.map { (Self.canonicalThreadURL(for: $0), $0) })
        let remoteCanonicalURLs = Set(remoteByCanonicalURL.keys)
        let removedFavorites = favorites.filter { localFavorite in
            !remoteCanonicalURLs.contains(Self.canonicalThreadURL(for: localFavorite))
        }
        archivedMetadata = Self.upsertingArchiveEntries(from: removedFavorites, into: archivedMetadata)
            .filter { !restoredArchiveURLs.contains($0.canonicalThreadURL) }

        favorites = remoteNewFavorites + favorites.compactMap { localFavorite in
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

            return nil
        }
    }

    private static func canonicalThreadURL(for favorite: Favorite) -> URL {
        ReaderCacheIdentity.canonicalThreadURL(from: favorite.url)
    }

    private static func upsertingArchiveEntries(
        from favorites: [Favorite],
        into archivedMetadata: [FavoriteMetadataArchiveEntry]
    ) -> [FavoriteMetadataArchiveEntry] {
        var entriesByURL = Dictionary(uniqueKeysWithValues: archivedMetadata.map { ($0.canonicalThreadURL, $0) })
        for favorite in favorites {
            let entry = FavoriteMetadataArchiveEntry(favorite: favorite)
            entriesByURL[entry.canonicalThreadURL] = entry
        }
        return entriesByURL.values.sorted { lhs, rhs in
            lhs.canonicalThreadURL.absoluteString < rhs.canonicalThreadURL.absoluteString
        }
    }
}

private extension Favorite {
    mutating func applyArchivedMetadata(
        _ archive: FavoriteMetadataArchiveEntry,
        validCollectionIDs: Set<String>
    ) {
        displayName = archive.displayName
        lastPage = archive.lastPage
        lastView = archive.lastView
        lastChapter = archive.lastChapter
        authorID = archive.authorID
        novelResumePoint = archive.novelResumePoint
        isHidden = archive.isHidden
        type = archive.type
        lastMangaURL = archive.lastMangaURL
        parentCollectionID = archive.parentCollectionID.flatMap { validCollectionIDs.contains($0) ? $0 : nil }
        manualOrder = archive.manualOrder
        lastReadAt = archive.lastReadAt
    }
}
