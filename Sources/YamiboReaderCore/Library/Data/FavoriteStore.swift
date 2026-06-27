import Foundation

public protocol FavoriteStoring: Sendable {
    func loadFavorites() async -> [Favorite]
    func loadCollections() async -> [FavoriteCollection]
    func loadTags() async -> [FavoriteTag]
    func loadLibrarySnapshot() async -> FavoriteLibrarySnapshot
    func saveLibrarySnapshot(_ snapshot: FavoriteLibrarySnapshot) async throws
    func saveFavorites(_ favorites: [Favorite]) async throws
    func createTag(name: String, color: FavoriteTagColor, date: Date) async throws -> FavoriteLibrarySnapshot
    func updateTag(id: String, name: String, color: FavoriteTagColor, date: Date) async throws -> FavoriteLibrarySnapshot
    func deleteTag(id: String) async throws -> FavoriteLibrarySnapshot
    func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite]
    func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite]
    func reorderFavorites(in parentCollectionID: String?, visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite]
    func reorderRootEntries(visibleEntryKeys: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> FavoriteLibrarySnapshot
    func reorderTags(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> FavoriteLibrarySnapshot
    func createCollection(name: String, favoriteIDs: [String]) async throws -> FavoriteLibrarySnapshot
    func moveFavorites(ids: [String], toCollectionID: String?) async throws -> FavoriteLibrarySnapshot
    func dissolveCollections(ids: [String]) async throws -> FavoriteLibrarySnapshot
    func setCollectionName(_ name: String, for collectionID: String) async throws -> FavoriteLibrarySnapshot
    func setCollectionHidden(_ isHidden: Bool, for collectionID: String) async throws -> FavoriteLibrarySnapshot
    func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite]
    func setDisplayName(_ displayName: String?, for favoriteID: String) async throws -> [Favorite]
    func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite]
    func setTagIDs(_ tagIDs: [String], for favoriteID: String) async throws -> [Favorite]
    func setTagIDs(_ tagIDs: [String], forFavoriteIDs favoriteIDs: [String]) async throws -> FavoriteLibrarySnapshot
    func deleteFavorite(id: String) async throws -> [Favorite]
    func deleteFavorites(ids: [String]) async throws -> FavoriteLibrarySnapshot
    func favorite(for url: URL) async -> Favorite?
    func favorite(id: String) async -> Favorite?
    func markLastReadAt(for favoriteID: String, date: Date) async throws -> [Favorite]
    func updateNovelReadingPosition(_ position: NovelReadingPosition) async throws -> Favorite
    func updateMangaProgress(for url: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int) async throws -> Favorite
    func clearAll() async throws
}

public actor FavoriteStore: FavoriteStoring {
    public static let didChangeNotification = Notification.Name("yamibo.favoriteStore.didChange")
    public static let changeIDUserInfoKey = "changeID"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let collectionsKey: String
    private let tagsKey: String
    private let archivedMetadataKey: String
    private let syncMetadataKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    fileprivate static let rootContainerKey = "__root__"
    fileprivate static let collectionEntryPrefix = "collection:"
    fileprivate static let favoriteEntryPrefix = "favorite:"

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.favorites") {
        self.defaults = defaults
        self.key = key
        collectionsKey = "\(key).collections"
        tagsKey = "\(key).tags"
        archivedMetadataKey = "\(key).archivedMetadata"
        syncMetadataKey = "\(key).syncMetadata"
    }

    public func loadFavorites() async -> [Favorite] {
        let favorites = decodedValue([Favorite].self, forKey: key) ?? []
        let collections = decodedValue([FavoriteCollection].self, forKey: collectionsKey) ?? []
        let tags = decodedValue([FavoriteTag].self, forKey: tagsKey) ?? []
        let validCollectionIDs = Set(collections.map(\.id))
        let validTagIDs = Set(tags.map(\.id))
        return sanitizeLoadedFavorites(
            favorites,
            collections: collections,
            validCollectionIDs: validCollectionIDs,
            validTagIDs: validTagIDs
        )
    }

    public func loadCollections() async -> [FavoriteCollection] {
        sanitizeLoadedCollections(decodedValue([FavoriteCollection].self, forKey: collectionsKey) ?? [])
    }

    public func loadTags() async -> [FavoriteTag] {
        sanitizeTagsForPersistence(decodedValue([FavoriteTag].self, forKey: tagsKey) ?? [])
    }

    public func loadLibrarySnapshot() async -> FavoriteLibrarySnapshot {
        loadLibrarySnapshotSync()
    }

    private func loadLibrarySnapshotSync() -> FavoriteLibrarySnapshot {
        let collections = sanitizeLoadedCollections(decodedValue([FavoriteCollection].self, forKey: collectionsKey) ?? [])
        let tags = sanitizeTagsForPersistence(decodedValue([FavoriteTag].self, forKey: tagsKey) ?? [])
        let validTagIDs = Set(tags.map(\.id))
        let favorites = sanitizeLoadedFavorites(
            decodedValue([Favorite].self, forKey: key) ?? [],
            collections: collections,
            validCollectionIDs: Set(collections.map(\.id)),
            validTagIDs: validTagIDs
        )
        return FavoriteLibrarySnapshot(
            favorites: favorites,
            collections: collections,
            tags: tags,
            archivedMetadata: sanitizeArchivedMetadata(
                loadArchivedMetadata(),
                validTagIDs: validTagIDs
            ),
            syncMetadata: loadSyncMetadata()
        )
    }

    public func saveFavorites(_ favorites: [Favorite]) async throws {
        let collections = await loadCollections()
        _ = try persistLibrary(
            favorites: favorites,
            collections: collections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func saveLibrarySnapshot(_ snapshot: FavoriteLibrarySnapshot) async throws {
        _ = try persistLibrary(
            favorites: snapshot.favorites,
            collections: snapshot.collections,
            tags: snapshot.tags,
            archivedMetadata: snapshot.archivedMetadata,
            syncMetadata: snapshot.syncMetadata
        )
    }

    public func createTag(
        name: String,
        color: FavoriteTagColor,
        date: Date = .now
    ) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let normalizedName = try validateTagName(name, existingTags: snapshot.tags, excludingTagID: nil)
        let shiftedTags = snapshot.tags.map { tag in
            var tag = tag
            tag.manualOrder += 1
            return tag
        }
        let tag = FavoriteTag(
            name: normalizedName,
            color: color,
            manualOrder: 0,
            createdAt: date,
            updatedAt: date
        )
        return try persistLibrary(
            favorites: snapshot.favorites,
            collections: snapshot.collections,
            tags: [tag] + shiftedTags,
            archivedMetadata: snapshot.archivedMetadata,
            metadataUpdate: Self.touchUserOwnedChanges(date: date)
        )
    }

    public func updateTag(
        id tagID: String,
        name: String,
        color: FavoriteTagColor,
        date: Date = .now
    ) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let normalizedName = try validateTagName(name, existingTags: snapshot.tags, excludingTagID: tagID)
        var didChange = false
        let updatedTags = snapshot.tags.map { tag in
            guard tag.id == tagID else { return tag }
            var tag = tag
            if tag.name != normalizedName || tag.color != color {
                tag.name = normalizedName
                tag.color = color
                tag.updatedAt = date
                didChange = true
            }
            return tag
        }
        guard didChange else { return snapshot }
        return try persistLibrary(
            favorites: snapshot.favorites,
            collections: snapshot.collections,
            tags: updatedTags,
            archivedMetadata: snapshot.archivedMetadata,
            metadataUpdate: Self.touchUserOwnedChanges(date: date)
        )
    }

    public func deleteTag(id tagID: String) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        guard snapshot.tags.contains(where: { $0.id == tagID }) else { return snapshot }
        let updatedTags = snapshot.tags.filter { $0.id != tagID }
        let updatedFavorites = snapshot.favorites.map { favorite in
            var favorite = favorite
            favorite.tagIDs.removeAll { $0 == tagID }
            return favorite
        }
        let updatedArchivedMetadata = snapshot.archivedMetadata.map { entry in
            var entry = entry
            entry.tagIDs.removeAll { $0 == tagID }
            return entry
        }
        return try persistLibrary(
            favorites: updatedFavorites,
            collections: snapshot.collections,
            tags: updatedTags,
            archivedMetadata: updatedArchivedMetadata,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite] {
        var library = FavoriteLibrary(snapshot: await loadLibrarySnapshot())
        library.reconcileRemoteFavorites(favorites)
        let snapshot = try persistLibrary(
            favorites: library.snapshot.favorites,
            collections: library.snapshot.collections,
            tags: library.snapshot.tags,
            archivedMetadata: library.snapshot.archivedMetadata,
            metadataUpdate: Self.touchRemoteFavorites(date: .now)
        )
        return snapshot.favorites
    }

    public func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite] {
        try await reorderFavorites(in: nil, visibleIDs: visibleIDs, fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func reorderFavorites(
        in parentCollectionID: String?,
        visibleIDs: [String],
        fromOffsets: IndexSet,
        toOffset: Int
    ) async throws -> [Favorite] {
        guard !visibleIDs.isEmpty, !fromOffsets.isEmpty else {
            return await loadFavorites()
        }

        let snapshot = await loadLibrarySnapshot()
        var rootFavorites = orderedFavorites(in: nil, from: snapshot.favorites)
        var favoritesByCollection = favoritesByCollection(from: snapshot.favorites, collections: snapshot.collections)
        let currentFavorites = orderedFavorites(in: parentCollectionID, from: snapshot.favorites)
        let favoritesByID = Dictionary(uniqueKeysWithValues: currentFavorites.map { ($0.id, $0) })
        var visibleFavorites = visibleIDs.compactMap { favoritesByID[$0] }
        guard visibleFavorites.count > 1 else { return snapshot.favorites }

        visibleFavorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let visibleSet = Set(visibleIDs)
        var iterator = visibleFavorites.makeIterator()
        let reorderedFavorites = currentFavorites.map { favorite in
            guard visibleSet.contains(favorite.id) else { return favorite }
            return iterator.next() ?? favorite
        }
        let normalizedReorderedFavorites = reorderedFavorites.enumerated().map { index, favorite in
            var favorite = favorite
            favorite.manualOrder = index
            if parentCollectionID == nil {
                favorite.parentCollectionID = nil
            }
            return favorite
        }

        if let parentCollectionID {
            favoritesByCollection[parentCollectionID] = normalizedReorderedFavorites
        } else {
            rootFavorites = normalizedReorderedFavorites
        }

        let updatedSnapshot = try persistLibrary(
            favorites: flattenFavorites(
                rootFavorites: rootFavorites,
                collections: snapshot.collections,
                favoritesByCollection: favoritesByCollection
            ),
            collections: snapshot.collections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
        return updatedSnapshot.favorites
    }

    public func reorderRootEntries(
        visibleEntryKeys: [String],
        fromOffsets: IndexSet,
        toOffset: Int
    ) async throws -> FavoriteLibrarySnapshot {
        guard !visibleEntryKeys.isEmpty, !fromOffsets.isEmpty else {
            return await loadLibrarySnapshot()
        }

        let snapshot = await loadLibrarySnapshot()
        let rootFavorites = orderedFavorites(in: nil, from: snapshot.favorites)
        let visibleSet = Set(visibleEntryKeys)
        let allEntries = rootEntries(from: snapshot.collections, rootFavorites: rootFavorites)
        let entriesByKey = Dictionary(uniqueKeysWithValues: allEntries.map { ($0.key, $0) })
        var visibleEntries = visibleEntryKeys.compactMap { entriesByKey[$0] }
        guard visibleEntries.count > 1 else { return snapshot }

        visibleEntries.move(fromOffsets: fromOffsets, toOffset: toOffset)
        var iterator = visibleEntries.makeIterator()
        let reorderedEntries = allEntries.map { entry in
            guard visibleSet.contains(entry.key) else { return entry }
            return iterator.next() ?? entry
        }

        var reorderedCollections: [FavoriteCollection] = []
        var reorderedRootFavorites: [Favorite] = []
        for (index, entry) in reorderedEntries.enumerated() {
            switch entry {
            case let .collection(collection):
                var collection = collection
                collection.manualOrder = index
                reorderedCollections.append(collection)
            case let .favorite(favorite):
                var favorite = favorite
                favorite.parentCollectionID = nil
                favorite.manualOrder = index
                reorderedRootFavorites.append(favorite)
            }
        }
        let favoritesByCollection = favoritesByCollection(from: snapshot.favorites, collections: snapshot.collections)

        return try persistLibrary(
            favorites: flattenFavorites(
                rootFavorites: reorderedRootFavorites,
                collections: reorderedCollections,
                favoritesByCollection: favoritesByCollection
            ),
            collections: reorderedCollections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func reorderTags(
        visibleIDs: [String],
        fromOffsets: IndexSet,
        toOffset: Int
    ) async throws -> FavoriteLibrarySnapshot {
        try await reorderTags(visibleIDs: visibleIDs, fromOffsets: fromOffsets, toOffset: toOffset, date: .now)
    }

    public func reorderTags(
        visibleIDs: [String],
        fromOffsets: IndexSet,
        toOffset: Int,
        date: Date
    ) async throws -> FavoriteLibrarySnapshot {
        guard !visibleIDs.isEmpty, !fromOffsets.isEmpty else {
            return await loadLibrarySnapshot()
        }

        let snapshot = await loadLibrarySnapshot()
        let orderedTags = sanitizeTagsForPersistence(snapshot.tags)
        let tagsByID = Dictionary(uniqueKeysWithValues: orderedTags.map { ($0.id, $0) })
        let visibleSet = Set(visibleIDs)
        var visibleTags = visibleIDs.compactMap { tagsByID[$0] }
        guard visibleTags.count > 1 else { return snapshot }

        let movedTagIDs = Set(fromOffsets.compactMap { index in
            visibleTags.indices.contains(index) ? visibleTags[index].id : nil
        })
        visibleTags.move(fromOffsets: fromOffsets, toOffset: toOffset)
        var iterator = visibleTags.makeIterator()
        var reorderedTags = orderedTags.map { tag in
            guard visibleSet.contains(tag.id) else { return tag }
            return iterator.next() ?? tag
        }

        for index in reorderedTags.indices {
            reorderedTags[index].manualOrder = index
            if movedTagIDs.contains(reorderedTags[index].id) {
                reorderedTags[index].updatedAt = date
            }
        }

        return try persistLibrary(
            favorites: snapshot.favorites,
            collections: snapshot.collections,
            tags: reorderedTags,
            archivedMetadata: snapshot.archivedMetadata,
            metadataUpdate: Self.touchUserOwnedChanges(date: date)
        )
    }

    public func createCollection(name: String, favoriteIDs: [String]) async throws -> FavoriteLibrarySnapshot {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_store.collection_name_empty"))
        }

        let snapshot = await loadLibrarySnapshot()
        let selectedIDs = Set(favoriteIDs)
        let rootFavorites = orderedFavorites(in: nil, from: snapshot.favorites)
        let selectedFavorites = rootFavorites.filter { selectedIDs.contains($0.id) }
        guard !selectedFavorites.isEmpty else { return snapshot }

        var remainingRootFavorites = rootFavorites.filter { !selectedIDs.contains($0.id) }
        var existingCollections = orderedCollections(snapshot.collections)
        shiftRootEntryOrders(rootFavorites: &remainingRootFavorites, collections: &existingCollections, by: 1)
        var collection = FavoriteCollection(name: trimmedName)
        collection.manualOrder = 0
        var favoritesByCollection = favoritesByCollection(from: snapshot.favorites, collections: snapshot.collections)
        favoritesByCollection[collection.id] = selectedFavorites.enumerated().map { index, favorite in
            var favorite = favorite
            favorite.parentCollectionID = collection.id
            favorite.manualOrder = index
            return favorite
        }

        return try persistLibrary(
            favorites: flattenFavorites(
                rootFavorites: remainingRootFavorites,
                collections: [collection] + existingCollections,
                favoritesByCollection: favoritesByCollection
            ),
            collections: [collection] + existingCollections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func moveFavorites(ids: [String], toCollectionID: String?) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let collections = orderedCollections(snapshot.collections)
        if let toCollectionID, !collections.contains(where: { $0.id == toCollectionID }) {
            return snapshot
        }

        let selectedIDs = Set(ids)
        guard !selectedIDs.isEmpty else { return snapshot }

        let selectedFavorites = snapshot.favorites.filter { selectedIDs.contains($0.id) }
        guard !selectedFavorites.isEmpty else { return snapshot }

        var rootFavorites = orderedFavorites(in: nil, from: snapshot.favorites).filter { !selectedIDs.contains($0.id) }
        var byCollection = favoritesByCollection(from: snapshot.favorites, collections: snapshot.collections)
        for collection in collections {
            byCollection[collection.id] = (byCollection[collection.id] ?? []).filter { !selectedIDs.contains($0.id) }
        }

        let movedFavorites = selectedFavorites.map { favorite in
            var favorite = favorite
            favorite.parentCollectionID = toCollectionID
            return favorite
        }

        if let toCollectionID {
            let nextOrder = (byCollection[toCollectionID]?.map(\.manualOrder).max() ?? -1) + 1
            byCollection[toCollectionID, default: []].append(contentsOf: movedFavorites.enumerated().map { index, favorite in
                var favorite = favorite
                favorite.manualOrder = nextOrder + index
                return favorite
            })
        } else {
            let nextOrder = nextRootManualOrder(rootFavorites: rootFavorites, collections: collections)
            rootFavorites.append(contentsOf: movedFavorites.enumerated().map { index, favorite in
                var favorite = favorite
                favorite.manualOrder = nextOrder + index
                return favorite
            })
        }

        return try persistLibrary(
            favorites: flattenFavorites(
                rootFavorites: rootFavorites,
                collections: collections,
                favoritesByCollection: byCollection
            ),
            collections: collections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func dissolveCollections(ids: [String]) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let selectedIDs = Set(ids)
        guard !selectedIDs.isEmpty else { return snapshot }

        let collections = orderedCollections(snapshot.collections)
        let remainingCollections = collections.filter { !selectedIDs.contains($0.id) }
        var rootFavorites = orderedFavorites(in: nil, from: snapshot.favorites)
        var byCollection = favoritesByCollection(from: snapshot.favorites, collections: snapshot.collections)
        let nextOrder = nextRootManualOrder(rootFavorites: rootFavorites, collections: remainingCollections)
        let releasedFavorites = collections
            .filter { selectedIDs.contains($0.id) }
            .flatMap { byCollection[$0.id] ?? [] }
            .enumerated()
            .map { index, favorite in
                var favorite = favorite
                favorite.parentCollectionID = nil
                favorite.manualOrder = nextOrder + index
                return favorite
            }

        rootFavorites.append(contentsOf: releasedFavorites)
        selectedIDs.forEach { byCollection.removeValue(forKey: $0) }

        return try persistLibrary(
            favorites: flattenFavorites(
                rootFavorites: rootFavorites,
                collections: remainingCollections,
                favoritesByCollection: byCollection
            ),
            collections: remainingCollections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func setCollectionName(_ name: String, for collectionID: String) async throws -> FavoriteLibrarySnapshot {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_store.collection_name_empty"))
        }

        let snapshot = await loadLibrarySnapshot()
        let updatedCollections = snapshot.collections.map { collection in
            guard collection.id == collectionID else { return collection }
            var collection = collection
            collection.name = trimmedName
            return collection
        }
        return try persistLibrary(
            favorites: snapshot.favorites,
            collections: updatedCollections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func setCollectionHidden(_ isHidden: Bool, for collectionID: String) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let updatedCollections = snapshot.collections.map { collection in
            guard collection.id == collectionID else { return collection }
            var collection = collection
            collection.isHidden = isHidden
            return collection
        }
        return try persistLibrary(
            favorites: snapshot.favorites,
            collections: updatedCollections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite] {
        let snapshot = await loadLibrarySnapshot()
        let updated = snapshot.favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.isHidden = isHidden
            return favorite
        }
        return try persistLibrary(
            favorites: updated,
            collections: snapshot.collections,
            metadataUpdate: Self.touchFavoriteMetadata(favoriteIDs: Set([favoriteID]), date: .now)
        ).favorites
    }

    public func setDisplayName(_ displayName: String?, for favoriteID: String) async throws -> [Favorite] {
        var library = FavoriteLibrary(snapshot: await loadLibrarySnapshot())
        library.setDisplayName(displayName, for: favoriteID)
        return try persistLibrary(
            favorites: library.snapshot.favorites,
            collections: library.snapshot.collections,
            tags: library.snapshot.tags,
            archivedMetadata: library.snapshot.archivedMetadata,
            metadataUpdate: Self.touchFavoriteMetadata(favoriteIDs: Set([favoriteID]), date: .now)
        ).favorites
    }

    public func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite] {
        let snapshot = await loadLibrarySnapshot()
        let updated = snapshot.favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.type = type
            return favorite
        }
        return try persistLibrary(
            favorites: updated,
            collections: snapshot.collections,
            metadataUpdate: Self.touchFavoriteMetadata(favoriteIDs: Set([favoriteID]), date: .now)
        ).favorites
    }

    public func setTagIDs(_ tagIDs: [String], for favoriteID: String) async throws -> [Favorite] {
        try await setTagIDs(tagIDs, forFavoriteIDs: [favoriteID], date: .now).favorites
    }

    public func setTagIDs(_ tagIDs: [String], forFavoriteIDs favoriteIDs: [String]) async throws -> FavoriteLibrarySnapshot {
        try await setTagIDs(tagIDs, forFavoriteIDs: favoriteIDs, date: .now)
    }

    public func setTagIDs(
        _ tagIDs: [String],
        forFavoriteIDs favoriteIDs: [String],
        date: Date
    ) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let selectedFavoriteIDs = Set(favoriteIDs)
        guard !selectedFavoriteIDs.isEmpty else { return snapshot }
        let validTagIDs = Set(snapshot.tags.map(\.id))
        let normalizedTagIDs = sanitizedTagIDs(tagIDs, validTagIDs: validTagIDs)
        let updated = snapshot.favorites.map { favorite in
            guard selectedFavoriteIDs.contains(favorite.id) else { return favorite }
            var favorite = favorite
            favorite.tagIDs = normalizedTagIDs
            return favorite
        }
        let updatedTags = tagsRefreshingAssociationChanges(
            snapshot.tags,
            before: snapshot.favorites,
            after: updated,
            date: date
        )
        return try persistLibrary(
            favorites: updated,
            collections: snapshot.collections,
            tags: updatedTags,
            metadataUpdate: Self.touchUserOwnedChanges(date: date)
        )
    }

    public func deleteFavorite(id favoriteID: String) async throws -> [Favorite] {
        try await deleteFavorites(ids: [favoriteID]).favorites
    }

    public func deleteFavorites(ids: [String]) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let selectedIDs = Set(ids)
        guard !selectedIDs.isEmpty else { return snapshot }

        let updatedFavorites = snapshot.favorites.filter { !selectedIDs.contains($0.id) }
        return try persistLibrary(
            favorites: updatedFavorites,
            collections: snapshot.collections,
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    public func favorite(for url: URL) async -> Favorite? {
        await loadFavorites().first { favorite in
            favorite.url == url || favorite.id == url.absoluteString
        }
    }

    public func favorite(id: String) async -> Favorite? {
        await loadFavorites().first { $0.id == id }
    }

    public func markLastReadAt(for favoriteID: String, date: Date = .now) async throws -> [Favorite] {
        let snapshot = await loadLibrarySnapshot()
        let updated = snapshot.favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.lastReadAt = date
            return favorite
        }
        return try persistLibrary(
            favorites: updated,
            collections: snapshot.collections,
            metadataUpdate: Self.touchLastReadAt(favoriteIDs: Set([favoriteID]), date: date)
        ).favorites
    }

    public func updateNovelReadingPosition(_ position: NovelReadingPosition) async throws -> Favorite {
        guard let favorite = try await updateNovelReadingPosition(position, createIfMissing: true) else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_store.save_reader_progress_failed"))
        }
        return favorite
    }

    public func updateNovelReadingPosition(
        _ position: NovelReadingPosition,
        createIfMissing: Bool
    ) async throws -> Favorite? {
        let snapshot = await loadLibrarySnapshot()
        var favorites = snapshot.favorites
        let resumePoint = position.resumePoint
        let view = resumePoint?.view ?? position.view
        let novelMaxView = position.maxView.map { max(view, $0) }
        let chapterTitle = resumePoint?.chapterTitle ?? position.chapterTitle
        let authorID = resumePoint?.authorID ?? position.authorID

        if let index = favorites.firstIndex(where: {
            $0.url == position.threadURL || $0.id == position.threadURL.absoluteString
        }) {
            favorites[index].lastView = view
            favorites[index].mangaPageIndex = 0
            favorites[index].lastChapter = chapterTitle
            favorites[index].authorID = authorID
            favorites[index].novelResumePoint = resumePoint
            favorites[index].novelMaxView = novelMaxView
            favorites[index].novelDocumentSurfaceProgressPercent = position.documentSurfaceProgressPercent
            favorites[index].lastMangaURL = nil
            favorites[index].type = .novel
            return try persistLibrary(
                favorites: favorites,
                collections: snapshot.collections,
                metadataUpdate: Self.touchReadingPosition(canonicalURLKeys: Set([Self.canonicalURLKey(for: position.threadURL)]), date: .now)
            ).favorites[index]
        }

        guard createIfMissing else { return nil }

        var favorite = Favorite(
            title: position.threadURL.absoluteString,
            url: position.threadURL,
            mangaPageIndex: 0,
            lastView: view,
            lastChapter: chapterTitle,
            authorID: authorID,
            novelResumePoint: resumePoint,
            novelMaxView: novelMaxView,
            novelDocumentSurfaceProgressPercent: position.documentSurfaceProgressPercent,
            isHidden: false,
            type: .novel
        )
        favorite.parentCollectionID = nil
        favorites.append(favorite)
        return try persistLibrary(
            favorites: favorites,
            collections: snapshot.collections,
            metadataUpdate: Self.touchReadingPositionAndRemoteFavorites(
                canonicalURLKeys: Set([Self.canonicalURLKey(for: position.threadURL)]),
                date: .now
            )
        ).favorites.last ?? favorite
    }

    public func updateMangaProgress(for url: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int) async throws -> Favorite {
        guard let favorite = try await updateMangaProgress(
            for: url,
            chapterURL: chapterURL,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            createIfMissing: true
        ) else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_store.save_manga_progress_failed"))
        }
        return favorite
    }

    public func updateMangaProgress(for url: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int, createIfMissing: Bool) async throws -> Favorite? {
        let snapshot = await loadLibrarySnapshot()
        var favorites = snapshot.favorites

        if let index = favorites.firstIndex(where: { $0.url == url || $0.id == url.absoluteString }) {
            favorites[index].lastMangaURL = chapterURL
            favorites[index].lastChapter = chapterTitle
            favorites[index].mangaPageIndex = max(0, pageIndex)
            favorites[index].novelResumePoint = nil
            favorites[index].novelMaxView = nil
            favorites[index].type = .manga
            return try persistLibrary(
                favorites: favorites,
                collections: snapshot.collections,
                metadataUpdate: Self.touchReadingPosition(canonicalURLKeys: Set([Self.canonicalURLKey(for: url)]), date: .now)
            ).favorites[index]
        }

        guard createIfMissing else { return nil }

        var favorite = Favorite(
            title: chapterTitle,
            url: url,
            mangaPageIndex: max(0, pageIndex),
            lastView: 1,
            lastChapter: chapterTitle,
            authorID: nil,
            novelResumePoint: nil,
            novelMaxView: nil,
            isHidden: false,
            type: .manga,
            lastMangaURL: chapterURL
        )
        favorite.parentCollectionID = nil
        favorites.append(favorite)
        return try persistLibrary(
            favorites: favorites,
            collections: snapshot.collections,
            metadataUpdate: Self.touchReadingPositionAndRemoteFavorites(
                canonicalURLKeys: Set([Self.canonicalURLKey(for: url)]),
                date: .now
            )
        ).favorites.last ?? favorite
    }

    public func clearAll() async throws {
        _ = try persistLibrary(
            favorites: [],
            collections: [],
            tags: [],
            archivedMetadata: [],
            metadataUpdate: Self.touchUserOwnedChanges(date: .now)
        )
    }

    private func persistLibrary(
        favorites: [Favorite],
        collections: [FavoriteCollection],
        tags: [FavoriteTag]? = nil,
        archivedMetadata: [FavoriteMetadataArchiveEntry]? = nil,
        syncMetadata: FavoriteLibrarySyncMetadata? = nil,
        metadataUpdate: ((inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void)? = nil
    ) throws -> FavoriteLibrarySnapshot {
        let previousSnapshot = loadLibrarySnapshotSync()
        let sanitizedCollections = sanitizeCollectionsForPersistence(collections)
        let sanitizedTags = sanitizeTagsForPersistence(tags ?? (decodedValue([FavoriteTag].self, forKey: tagsKey) ?? []))
        let validCollectionIDs = Set(sanitizedCollections.map(\.id))
        let validTagIDs = Set(sanitizedTags.map(\.id))
        let sanitizedFavorites = sanitizeFavoritesForPersistence(
            favorites,
            validCollectionIDs: validCollectionIDs,
            validTagIDs: validTagIDs
        )
        let resolvedArchivedMetadata = sanitizeArchivedMetadata(
            archivedMetadata ?? loadArchivedMetadata(),
            validTagIDs: validTagIDs
        )
        var resolvedSyncMetadata = syncMetadata ?? loadSyncMetadata()
        let nextSnapshotWithoutMetadata = FavoriteLibrarySnapshot(
            favorites: sanitizedFavorites,
            collections: sanitizedCollections,
            tags: sanitizedTags,
            archivedMetadata: resolvedArchivedMetadata
        )
        metadataUpdate?(&resolvedSyncMetadata, previousSnapshot, nextSnapshotWithoutMetadata)

        do {
            let favoritesData = try encoder.encode(sanitizedFavorites)
            let collectionsData = try encoder.encode(sanitizedCollections)
            let tagsData = try encoder.encode(sanitizedTags)
            let archivedMetadataData = try encoder.encode(resolvedArchivedMetadata)
            let syncMetadataData = try encoder.encode(resolvedSyncMetadata)
            defaults.set(favoritesData, forKey: key)
            defaults.set(collectionsData, forKey: collectionsKey)
            defaults.set(tagsData, forKey: tagsKey)
            defaults.set(archivedMetadataData, forKey: archivedMetadataKey)
            defaults.set(syncMetadataData, forKey: syncMetadataKey)
            postChangeNotification()
            return FavoriteLibrarySnapshot(
                favorites: sanitizedFavorites,
                collections: sanitizedCollections,
                tags: sanitizedTags,
                archivedMetadata: resolvedArchivedMetadata,
                syncMetadata: resolvedSyncMetadata
            )
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    private static func touchRemoteFavorites(
        date: Date
    ) -> (inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void {
        { metadata, _, _ in
            metadata.remoteFavoritesUpdatedAt = date
        }
    }

    private static func touchReadingPosition(
        canonicalURLKeys: Set<String>,
        date: Date
    ) -> (inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void {
        { metadata, _, _ in
            for key in canonicalURLKeys {
                metadata.readingPositionUpdatedAtByCanonicalURL[key] = date
            }
        }
    }

    private static func touchReadingPositionAndRemoteFavorites(
        canonicalURLKeys: Set<String>,
        date: Date
    ) -> (inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void {
        { metadata, _, _ in
            metadata.remoteFavoritesUpdatedAt = date
            for key in canonicalURLKeys {
                metadata.readingPositionUpdatedAtByCanonicalURL[key] = date
            }
        }
    }

    private static func touchFavoriteMetadata(
        favoriteIDs: Set<String>,
        date: Date
    ) -> (inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void {
        { metadata, previous, next in
            let previousRecords = favoriteClockRecords(from: previous)
            let nextRecords = favoriteClockRecords(from: next)
            for key in canonicalURLKeys(forFavoriteIDs: favoriteIDs, previous: previous, next: next) {
                guard previousRecords[key]?.favoriteMetadata != nextRecords[key]?.favoriteMetadata else { continue }
                metadata.favoriteMetadataUpdatedAtByCanonicalURL[key] = date
            }
        }
    }

    private static func touchLastReadAt(
        favoriteIDs: Set<String>,
        date: Date
    ) -> (inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void {
        { metadata, previous, next in
            for key in canonicalURLKeys(forFavoriteIDs: favoriteIDs, previous: previous, next: next) {
                metadata.lastReadAtUpdatedAtByCanonicalURL[key] = date
            }
        }
    }

    private static func touchUserOwnedChanges(
        date: Date
    ) -> (inout FavoriteLibrarySyncMetadata, FavoriteLibrarySnapshot, FavoriteLibrarySnapshot) -> Void {
        { metadata, previous, next in
            let previousVisibleFavoriteKeys = Set(previous.favorites.map { canonicalURLKey(for: $0.url) })
            let nextVisibleFavoriteKeys = Set(next.favorites.map { canonicalURLKey(for: $0.url) })
            if previousVisibleFavoriteKeys != nextVisibleFavoriteKeys {
                metadata.remoteFavoritesUpdatedAt = date
            }

            let previousRecords = favoriteClockRecords(from: previous)
            let nextRecords = favoriteClockRecords(from: next)
            for key in Set(previousRecords.keys).union(nextRecords.keys) {
                let previousRecord = previousRecords[key]
                let nextRecord = nextRecords[key]
                if previousRecord?.readingPosition != nextRecord?.readingPosition {
                    metadata.readingPositionUpdatedAtByCanonicalURL[key] = date
                }
                if previousRecord?.lastReadAt != nextRecord?.lastReadAt {
                    metadata.lastReadAtUpdatedAtByCanonicalURL[key] = date
                }
                if previousRecord?.favoriteMetadata != nextRecord?.favoriteMetadata {
                    metadata.favoriteMetadataUpdatedAtByCanonicalURL[key] = date
                }
                if previousRecord?.organization != nextRecord?.organization {
                    metadata.favoriteOrganizationUpdatedAtByCanonicalURL[key] = date
                }
            }

            let previousCollections = Dictionary(uniqueKeysWithValues: previous.collections.map { ($0.id, $0) })
            let nextCollections = Dictionary(uniqueKeysWithValues: next.collections.map { ($0.id, $0) })
            for id in Set(previousCollections.keys).union(nextCollections.keys) where previousCollections[id] != nextCollections[id] {
                metadata.collectionUpdatedAtByID[id] = date
            }

            let previousTags = Dictionary(uniqueKeysWithValues: previous.tags.map { ($0.id, $0) })
            let nextTags = Dictionary(uniqueKeysWithValues: next.tags.map { ($0.id, $0) })
            for id in Set(previousTags.keys).union(nextTags.keys) where previousTags[id] != nextTags[id] {
                metadata.tagUpdatedAtByID[id] = date
            }
        }
    }

    private static func canonicalURLKey(for url: URL) -> String {
        ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString
    }

    private static func canonicalURLKeys(
        forFavoriteIDs favoriteIDs: Set<String>,
        previous: FavoriteLibrarySnapshot,
        next: FavoriteLibrarySnapshot
    ) -> Set<String> {
        let favorites = previous.favorites + next.favorites
        return Set(favorites.compactMap { favorite in
            favoriteIDs.contains(favorite.id) ? canonicalURLKey(for: favorite.url) : nil
        })
    }

    private static func favoriteClockRecords(
        from snapshot: FavoriteLibrarySnapshot
    ) -> [String: FavoriteClockRecord] {
        var records: [String: FavoriteClockRecord] = [:]
        for favorite in snapshot.favorites {
            records[canonicalURLKey(for: favorite.url)] = FavoriteClockRecord(favorite: favorite)
        }
        for archive in snapshot.archivedMetadata {
            records[archive.canonicalThreadURL.absoluteString] = FavoriteClockRecord(archive: archive)
        }
        return records
    }

    private func loadArchivedMetadata() -> [FavoriteMetadataArchiveEntry] {
        decodedValue([FavoriteMetadataArchiveEntry].self, forKey: archivedMetadataKey) ?? []
    }

    private func loadSyncMetadata() -> FavoriteLibrarySyncMetadata {
        decodedValue(FavoriteLibrarySyncMetadata.self, forKey: syncMetadataKey) ?? FavoriteLibrarySyncMetadata()
    }


    private func decodedValue<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func sanitizeLoadedFavorites(
        _ favorites: [Favorite],
        collections: [FavoriteCollection],
        validCollectionIDs: Set<String>,
        validTagIDs: Set<String>
    ) -> [Favorite] {
        let sanitizedFavorites = favorites.map { favorite in
            var favorite = favorite
            if let parentCollectionID = favorite.parentCollectionID, !validCollectionIDs.contains(parentCollectionID) {
                favorite.parentCollectionID = nil
            }
            favorite.tagIDs = sanitizedTagIDs(favorite.tagIDs, validTagIDs: validTagIDs)
            return favorite
        }

        let rootFavorites = sanitizedFavorites.filter { $0.parentCollectionID == nil }
        if collections.isEmpty && rootFavorites.count > 1 && Set(rootFavorites.map(\.manualOrder)).count <= 1 {
            return sanitizedFavorites.enumerated().map { index, favorite in
                var favorite = favorite
                if favorite.parentCollectionID == nil {
                    favorite.manualOrder = index
                }
                return favorite
            }
        }

        return sanitizeFavoritesForPersistence(
            sanitizedFavorites,
            validCollectionIDs: validCollectionIDs,
            validTagIDs: validTagIDs
        )
    }

    private func sanitizeLoadedCollections(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
        if collections.count > 1 && Set(collections.map(\.manualOrder)).count <= 1 {
            return collections.enumerated().map { index, collection in
                var collection = collection
                collection.manualOrder = index
                return collection
            }
        }
        return collections
    }

    private func sanitizeFavoritesForPersistence(
        _ favorites: [Favorite],
        validCollectionIDs: Set<String>,
        validTagIDs: Set<String>
    ) -> [Favorite] {
        let rootFavorites = favorites
            .filter { favorite in
                favorite.parentCollectionID == nil || !validCollectionIDs.contains(favorite.parentCollectionID ?? "")
            }
            .map { favorite -> Favorite in
                var favorite = favorite
                favorite.parentCollectionID = nil
                favorite.tagIDs = sanitizedTagIDs(favorite.tagIDs, validTagIDs: validTagIDs)
                return favorite
            }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }

        var sanitized = rootFavorites
        for collectionID in validCollectionIDs.sorted() {
            let collectionFavorites = favorites
                .filter { $0.parentCollectionID == collectionID }
                .sorted { lhs, rhs in
                    if lhs.manualOrder != rhs.manualOrder {
                        return lhs.manualOrder < rhs.manualOrder
                    }
                    return lhs.id < rhs.id
                }
                .enumerated()
                .map { index, favorite in
                    var favorite = favorite
                    favorite.parentCollectionID = collectionID
                    favorite.tagIDs = sanitizedTagIDs(favorite.tagIDs, validTagIDs: validTagIDs)
                    favorite.manualOrder = index
                    return favorite
                }
            sanitized.append(contentsOf: collectionFavorites)
        }
        return sanitized
    }

    private func sanitizeTagsForPersistence(_ tags: [FavoriteTag]) -> [FavoriteTag] {
        tags.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private func sanitizeArchivedMetadata(
        _ archivedMetadata: [FavoriteMetadataArchiveEntry],
        validTagIDs: Set<String>
    ) -> [FavoriteMetadataArchiveEntry] {
        archivedMetadata.map { entry in
            var entry = entry
            entry.tagIDs = sanitizedTagIDs(entry.tagIDs, validTagIDs: validTagIDs)
            return entry
        }
    }

    private func sanitizedTagIDs(_ tagIDs: [String], validTagIDs: Set<String>) -> [String] {
        var seen: Set<String> = []
        return tagIDs.filter { tagID in
            guard validTagIDs.contains(tagID), !seen.contains(tagID) else { return false }
            seen.insert(tagID)
            return true
        }
    }

    private func tagsRefreshingAssociationChanges(
        _ tags: [FavoriteTag],
        before oldFavorites: [Favorite],
        after newFavorites: [Favorite],
        date: Date
    ) -> [FavoriteTag] {
        let oldAssociations = tagAssociations(from: oldFavorites)
        let newAssociations = tagAssociations(from: newFavorites)
        return tags.map { tag in
            guard oldAssociations[tag.id, default: []] != newAssociations[tag.id, default: []] else {
                return tag
            }
            var tag = tag
            tag.updatedAt = date
            return tag
        }
    }

    private func tagAssociations(from favorites: [Favorite]) -> [String: Set<String>] {
        var associations: [String: Set<String>] = [:]
        for favorite in favorites {
            for tagID in Set(favorite.tagIDs) {
                associations[tagID, default: []].insert(favorite.id)
            }
        }
        return associations
    }

    private func validateTagName(
        _ name: String,
        existingTags: [FavoriteTag],
        excludingTagID: String?
    ) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw YamiboError.persistenceFailed("标签名称不能为空")
        }
        guard normalizedName.count <= 20 else {
            throw YamiboError.persistenceFailed("标签名称不能超过 20 个字符")
        }
        let hasDuplicate = existingTags.contains { tag in
            tag.id != excludingTagID &&
            tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }
        guard !hasDuplicate else {
            throw YamiboError.persistenceFailed("标签名称已存在")
        }
        return normalizedName
    }

    private func sanitizeCollectionsForPersistence(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
        collections.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private func orderedCollections(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
        collections.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private func orderedFavorites(in parentCollectionID: String?, from favorites: [Favorite]) -> [Favorite] {
        favorites
            .filter { $0.parentCollectionID == parentCollectionID }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }

    private func favoritesByCollection(
        from favorites: [Favorite],
        collections: [FavoriteCollection]
    ) -> [String: [Favorite]] {
        Dictionary(
            uniqueKeysWithValues: orderedCollections(collections).map { collection in
                (collection.id, orderedFavorites(in: collection.id, from: favorites))
            }
        )
    }

    private func flattenFavorites(
        rootFavorites: [Favorite],
        collections: [FavoriteCollection],
        favoritesByCollection: [String: [Favorite]]
    ) -> [Favorite] {
        var flattened = rootFavorites.map { favorite -> Favorite in
            var favorite = favorite
            favorite.parentCollectionID = nil
            return favorite
        }

        for collection in orderedCollections(collections) {
            let favorites = favoritesByCollection[collection.id] ?? []
            flattened.append(contentsOf: favorites.map { favorite in
                var favorite = favorite
                favorite.parentCollectionID = collection.id
                return favorite
            })
        }

        return flattened
    }

    private func rootEntries(
        from collections: [FavoriteCollection],
        rootFavorites: [Favorite]
    ) -> [RootEntry] {
        (collections.map(RootEntry.collection) + rootFavorites.map(RootEntry.favorite)).sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.key < rhs.key
        }
    }

    private func nextRootManualOrder(rootFavorites: [Favorite], collections: [FavoriteCollection]) -> Int {
        let maxFavoriteOrder = rootFavorites.map(\.manualOrder).max() ?? -1
        let maxCollectionOrder = collections.map(\.manualOrder).max() ?? -1
        return max(maxFavoriteOrder, maxCollectionOrder) + 1
    }

    private func shiftRootEntryOrders(
        rootFavorites: inout [Favorite],
        collections: inout [FavoriteCollection],
        by delta: Int
    ) {
        rootFavorites = rootFavorites.map { favorite in
            var favorite = favorite
            favorite.manualOrder += delta
            return favorite
        }
        collections = collections.map { collection in
            var collection = collection
            collection.manualOrder += delta
            return collection
        }
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}

private enum RootEntry {
    case collection(FavoriteCollection)
    case favorite(Favorite)

    var manualOrder: Int {
        switch self {
        case let .collection(collection):
            collection.manualOrder
        case let .favorite(favorite):
            favorite.manualOrder
        }
    }

    var key: String {
        switch self {
        case let .collection(collection):
            "\(FavoriteStore.collectionEntryPrefix)\(collection.id)"
        case let .favorite(favorite):
            "\(FavoriteStore.favoriteEntryPrefix)\(favorite.id)"
        }
    }

    var collection: FavoriteCollection? {
        if case let .collection(collection) = self {
            return collection
        }
        return nil
    }

    var favorite: Favorite? {
        if case let .favorite(favorite) = self {
            return favorite
        }
        return nil
    }
}

private struct FavoriteClockRecord: Equatable {
    var readingPosition: FavoriteReadingPositionClockFields
    var lastReadAt: Date?
    var favoriteMetadata: FavoriteMetadataClockFields
    var organization: FavoriteOrganizationClockFields

    init(favorite: Favorite) {
        readingPosition = FavoriteReadingPositionClockFields(
            mangaPageIndex: favorite.mangaPageIndex,
            lastView: favorite.lastView,
            lastChapter: favorite.lastChapter,
            authorID: favorite.authorID,
            novelResumePoint: favorite.novelResumePoint,
            novelMaxView: favorite.novelMaxView,
            novelDocumentSurfaceProgressPercent: favorite.novelDocumentSurfaceProgressPercent,
            lastMangaURL: favorite.lastMangaURL
        )
        lastReadAt = favorite.lastReadAt
        favoriteMetadata = FavoriteMetadataClockFields(
            displayName: favorite.displayName,
            isHidden: favorite.isHidden,
            type: favorite.type
        )
        organization = FavoriteOrganizationClockFields(
            parentCollectionID: favorite.parentCollectionID,
            manualOrder: favorite.manualOrder,
            tagIDs: favorite.tagIDs
        )
    }

    init(archive: FavoriteMetadataArchiveEntry) {
        readingPosition = FavoriteReadingPositionClockFields(
            mangaPageIndex: archive.mangaPageIndex,
            lastView: archive.lastView,
            lastChapter: archive.lastChapter,
            authorID: archive.authorID,
            novelResumePoint: archive.novelResumePoint,
            novelMaxView: archive.novelMaxView,
            novelDocumentSurfaceProgressPercent: archive.novelDocumentSurfaceProgressPercent,
            lastMangaURL: archive.lastMangaURL
        )
        lastReadAt = archive.lastReadAt
        favoriteMetadata = FavoriteMetadataClockFields(
            displayName: archive.displayName,
            isHidden: archive.isHidden,
            type: archive.type
        )
        organization = FavoriteOrganizationClockFields(
            parentCollectionID: archive.parentCollectionID,
            manualOrder: archive.manualOrder,
            tagIDs: archive.tagIDs
        )
    }
}

private struct FavoriteReadingPositionClockFields: Equatable {
    var mangaPageIndex: Int
    var lastView: Int
    var lastChapter: String?
    var authorID: String?
    var novelResumePoint: ReaderResumePoint?
    var novelMaxView: Int?
    var novelDocumentSurfaceProgressPercent: Int?
    var lastMangaURL: URL?
}

private struct FavoriteMetadataClockFields: Equatable {
    var displayName: String?
    var isHidden: Bool
    var type: FavoriteType
}

private struct FavoriteOrganizationClockFields: Equatable {
    var parentCollectionID: String?
    var manualOrder: Int
    var tagIDs: [String]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }

        let movingElements = source.sorted().map { self[$0] }
        for index in source.sorted(by: >) {
            remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let targetIndex = Swift.max(0, Swift.min(count, destination - removedBeforeDestination))
        insert(contentsOf: movingElements, at: targetIndex)
    }
}
