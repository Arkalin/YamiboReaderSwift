import Foundation

public struct FavoriteLibrarySnapshot: Codable, Equatable, Sendable {
    public var favorites: [Favorite]
    public var collections: [FavoriteCollection]
    public var tags: [FavoriteTag]
    public var archivedMetadata: [FavoriteMetadataArchiveEntry]

    private enum CodingKeys: String, CodingKey {
        case favorites
        case collections
        case tags
        case archivedMetadata
    }

    public init(
        favorites: [Favorite],
        collections: [FavoriteCollection],
        tags: [FavoriteTag] = [],
        archivedMetadata: [FavoriteMetadataArchiveEntry] = []
    ) {
        self.favorites = favorites
        self.collections = collections
        self.tags = tags
        self.archivedMetadata = archivedMetadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([Favorite].self, forKey: .favorites)
        collections = try container.decode([FavoriteCollection].self, forKey: .collections)
        tags = try container.decodeIfPresent([FavoriteTag].self, forKey: .tags) ?? []
        archivedMetadata = try container.decodeIfPresent([FavoriteMetadataArchiveEntry].self, forKey: .archivedMetadata) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(collections, forKey: .collections)
        try container.encode(tags, forKey: .tags)
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
    public var tagIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case canonicalThreadURL
        case displayName
        case lastPage
        case lastView
        case lastChapter
        case authorID
        case novelResumePoint
        case isHidden
        case type
        case lastMangaURL
        case parentCollectionID
        case manualOrder
        case lastReadAt
        case tagIDs
    }

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
        lastReadAt: Date?,
        tagIDs: [String] = []
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
        self.tagIDs = tagIDs
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
            lastReadAt: favorite.lastReadAt,
            tagIDs: favorite.tagIDs
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalThreadURL = try container.decode(URL.self, forKey: .canonicalThreadURL)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        lastPage = max(0, try container.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0)
        lastView = max(1, try container.decodeIfPresent(Int.self, forKey: .lastView) ?? 1)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID)
        novelResumePoint = try container.decodeIfPresent(ReaderResumePoint.self, forKey: .novelResumePoint)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        type = try container.decodeIfPresent(FavoriteType.self, forKey: .type) ?? .unknown
        lastMangaURL = try container.decodeIfPresent(URL.self, forKey: .lastMangaURL)
        parentCollectionID = try container.decodeIfPresent(String.self, forKey: .parentCollectionID)
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        tagIDs = try container.decodeIfPresent([String].self, forKey: .tagIDs) ?? []
    }
}

public struct FavoriteLibrary: Equatable, Sendable {
    public private(set) var favorites: [Favorite]
    public private(set) var collections: [FavoriteCollection]
    public private(set) var tags: [FavoriteTag]
    public private(set) var archivedMetadata: [FavoriteMetadataArchiveEntry]

    public init(snapshot: FavoriteLibrarySnapshot) {
        favorites = snapshot.favorites
        collections = snapshot.collections
        tags = snapshot.tags
        archivedMetadata = snapshot.archivedMetadata
    }

    public var snapshot: FavoriteLibrarySnapshot {
        FavoriteLibrarySnapshot(
            favorites: favorites,
            collections: collections,
            tags: tags,
            archivedMetadata: archivedMetadata
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
        let validCollectionIDs = Set(collections.map(\.id))
        let validTagIDs = Set(tags.map(\.id))
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
                    remoteFavorite.applyArchivedMetadata(
                        archive,
                        validCollectionIDs: validCollectionIDs,
                        validTagIDs: validTagIDs
                    )
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
        archivedMetadata = Self.upsertingArchiveEntries(
            from: removedFavorites,
            into: archivedMetadata,
            validTagIDs: validTagIDs
        )
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
        into archivedMetadata: [FavoriteMetadataArchiveEntry],
        validTagIDs: Set<String>
    ) -> [FavoriteMetadataArchiveEntry] {
        var entriesByURL = Dictionary(uniqueKeysWithValues: archivedMetadata.map { ($0.canonicalThreadURL, $0) })
        for favorite in favorites {
            var entry = FavoriteMetadataArchiveEntry(favorite: favorite)
            entry.tagIDs = entry.tagIDs.filter { validTagIDs.contains($0) }
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
        validCollectionIDs: Set<String>,
        validTagIDs: Set<String>
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
        tagIDs = archive.tagIDs.filter { validTagIDs.contains($0) }
    }
}
