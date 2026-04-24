import Foundation

public struct FavoriteLibrarySnapshot: Equatable, Sendable {
    public var favorites: [Favorite]
    public var collections: [FavoriteCollection]

    public init(favorites: [Favorite], collections: [FavoriteCollection]) {
        self.favorites = favorites
        self.collections = collections
    }
}

public protocol FavoriteStoring: Sendable {
    func loadFavorites() async -> [Favorite]
    func loadCollections() async -> [FavoriteCollection]
    func loadLibrarySnapshot() async -> FavoriteLibrarySnapshot
    func saveFavorites(_ favorites: [Favorite]) async throws
    func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite]
    func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite]
    func reorderFavorites(in parentCollectionID: String?, visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite]
    func reorderRootEntries(visibleEntryKeys: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> FavoriteLibrarySnapshot
    func createCollection(name: String, favoriteIDs: [String]) async throws -> FavoriteLibrarySnapshot
    func moveFavorites(ids: [String], toCollectionID: String?) async throws -> FavoriteLibrarySnapshot
    func dissolveCollections(ids: [String]) async throws -> FavoriteLibrarySnapshot
    func setCollectionName(_ name: String, for collectionID: String) async throws -> FavoriteLibrarySnapshot
    func setCollectionHidden(_ isHidden: Bool, for collectionID: String) async throws -> FavoriteLibrarySnapshot
    func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite]
    func setDisplayName(_ displayName: String?, for favoriteID: String) async throws -> [Favorite]
    func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite]
    func deleteFavorite(id: String) async throws -> [Favorite]
    func deleteFavorites(ids: [String]) async throws -> FavoriteLibrarySnapshot
    func favorite(for url: URL) async -> Favorite?
    func favorite(id: String) async -> Favorite?
    func markLastReadAt(for favoriteID: String, date: Date) async throws -> [Favorite]
    func updateReadingProgress(for url: URL, progress: ReaderProgress) async throws -> Favorite
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    fileprivate static let rootContainerKey = "__root__"
    fileprivate static let collectionEntryPrefix = "collection:"
    fileprivate static let favoriteEntryPrefix = "favorite:"

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.favorites") {
        self.defaults = defaults
        self.key = key
        collectionsKey = "\(key).collections"
    }

    public func loadFavorites() async -> [Favorite] {
        let favorites = decodedValue([Favorite].self, forKey: key) ?? []
        let collections = decodedValue([FavoriteCollection].self, forKey: collectionsKey) ?? []
        let validCollectionIDs = Set(collections.map(\.id))
        return sanitizeLoadedFavorites(favorites, collections: collections, validCollectionIDs: validCollectionIDs)
    }

    public func loadCollections() async -> [FavoriteCollection] {
        sanitizeLoadedCollections(decodedValue([FavoriteCollection].self, forKey: collectionsKey) ?? [])
    }

    public func loadLibrarySnapshot() async -> FavoriteLibrarySnapshot {
        FavoriteLibrarySnapshot(
            favorites: await loadFavorites(),
            collections: await loadCollections()
        )
    }

    public func saveFavorites(_ favorites: [Favorite]) async throws {
        let collections = await loadCollections()
        _ = try persistLibrary(favorites: favorites, collections: collections)
    }

    public func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite] {
        let localFavorites = await loadFavorites()
        let localCollections = await loadCollections()
        let localIDs = Set(localFavorites.map(\.id))
        let minRootOrder = min(
            localFavorites.filter { $0.parentCollectionID == nil }.map(\.manualOrder).min() ?? 0,
            localCollections.map(\.manualOrder).min() ?? 0
        )

        let unsortedRemoteNewFavorites = favorites
            .compactMap { remoteFavorite -> Favorite? in
                guard !localIDs.contains(remoteFavorite.id) else { return nil }
                var remoteFavorite = remoteFavorite
                remoteFavorite.parentCollectionID = nil
                return remoteFavorite
            }
        let remoteNewFavorites = unsortedRemoteNewFavorites
            .enumerated()
            .map { offset, remoteFavorite in
                var remoteFavorite = remoteFavorite
                remoteFavorite.manualOrder = minRootOrder - unsortedRemoteNewFavorites.count + offset
                return remoteFavorite
            }
        let remoteByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })

        let mergedFavorites = remoteNewFavorites + localFavorites.compactMap { localFavorite in
            if let remoteFavorite = remoteByID[localFavorite.id] {
                var updated = localFavorite
                updated.title = remoteFavorite.title
                updated.url = remoteFavorite.url
                updated.remoteFavoriteID = remoteFavorite.remoteFavoriteID ?? updated.remoteFavoriteID
                if updated.type == .unknown {
                    updated.type = remoteFavorite.type
                }
                return updated
            }

            return localFavorite.isHidden ? localFavorite : nil
        }

        let snapshot = try persistLibrary(favorites: mergedFavorites, collections: localCollections)
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
            collections: snapshot.collections
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
            collections: reorderedCollections
        )
    }

    public func createCollection(name: String, favoriteIDs: [String]) async throws -> FavoriteLibrarySnapshot {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw YamiboError.persistenceFailed("合集名称不能为空")
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
            collections: [collection] + existingCollections
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
            collections: collections
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
            collections: remainingCollections
        )
    }

    public func setCollectionName(_ name: String, for collectionID: String) async throws -> FavoriteLibrarySnapshot {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw YamiboError.persistenceFailed("合集名称不能为空")
        }

        let snapshot = await loadLibrarySnapshot()
        let updatedCollections = snapshot.collections.map { collection in
            guard collection.id == collectionID else { return collection }
            var collection = collection
            collection.name = trimmedName
            return collection
        }
        return try persistLibrary(favorites: snapshot.favorites, collections: updatedCollections)
    }

    public func setCollectionHidden(_ isHidden: Bool, for collectionID: String) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let updatedCollections = snapshot.collections.map { collection in
            guard collection.id == collectionID else { return collection }
            var collection = collection
            collection.isHidden = isHidden
            return collection
        }
        return try persistLibrary(favorites: snapshot.favorites, collections: updatedCollections)
    }

    public func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite] {
        let snapshot = await loadLibrarySnapshot()
        let updated = snapshot.favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.isHidden = isHidden
            return favorite
        }
        return try persistLibrary(favorites: updated, collections: snapshot.collections).favorites
    }

    public func setDisplayName(_ displayName: String?, for favoriteID: String) async throws -> [Favorite] {
        let normalized = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let snapshot = await loadLibrarySnapshot()
        let updated = snapshot.favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.displayName = normalized
            return favorite
        }
        return try persistLibrary(favorites: updated, collections: snapshot.collections).favorites
    }

    public func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite] {
        let snapshot = await loadLibrarySnapshot()
        let updated = snapshot.favorites.map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.type = type
            return favorite
        }
        return try persistLibrary(favorites: updated, collections: snapshot.collections).favorites
    }

    public func deleteFavorite(id favoriteID: String) async throws -> [Favorite] {
        try await deleteFavorites(ids: [favoriteID]).favorites
    }

    public func deleteFavorites(ids: [String]) async throws -> FavoriteLibrarySnapshot {
        let snapshot = await loadLibrarySnapshot()
        let selectedIDs = Set(ids)
        guard !selectedIDs.isEmpty else { return snapshot }

        let updatedFavorites = snapshot.favorites.filter { !selectedIDs.contains($0.id) }
        return try persistLibrary(favorites: updatedFavorites, collections: snapshot.collections)
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
        return try persistLibrary(favorites: updated, collections: snapshot.collections).favorites
    }

    public func updateReadingProgress(for url: URL, progress: ReaderProgress) async throws -> Favorite {
        guard let favorite = try await updateReadingProgress(for: url, progress: progress, createIfMissing: true) else {
            throw YamiboError.persistenceFailed("未能保存阅读进度")
        }
        return favorite
    }

    public func updateReadingProgress(for url: URL, progress: ReaderProgress, createIfMissing: Bool) async throws -> Favorite? {
        let snapshot = await loadLibrarySnapshot()
        var favorites = snapshot.favorites

        if let index = favorites.firstIndex(where: { $0.url == url || $0.id == url.absoluteString }) {
            favorites[index].lastView = progress.view
            favorites[index].lastPage = progress.page
            favorites[index].lastChapter = progress.chapterTitle
            favorites[index].authorID = progress.authorID
            favorites[index].novelResumePoint = progress.resumePoint
            if favorites[index].type == .unknown {
                favorites[index].type = .novel
            }
            return try persistLibrary(favorites: favorites, collections: snapshot.collections).favorites[index]
        }

        guard createIfMissing else { return nil }

        var favorite = Favorite(
            title: url.absoluteString,
            url: url,
            lastPage: progress.page,
            lastView: progress.view,
            lastChapter: progress.chapterTitle,
            authorID: progress.authorID,
            novelResumePoint: progress.resumePoint,
            isHidden: false,
            type: .novel
        )
        favorite.parentCollectionID = nil
        favorites.append(favorite)
        return try persistLibrary(favorites: favorites, collections: snapshot.collections).favorites.last ?? favorite
    }

    public func updateMangaProgress(for url: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int) async throws -> Favorite {
        guard let favorite = try await updateMangaProgress(
            for: url,
            chapterURL: chapterURL,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            createIfMissing: true
        ) else {
            throw YamiboError.persistenceFailed("未能保存漫画进度")
        }
        return favorite
    }

    public func updateMangaProgress(for url: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int, createIfMissing: Bool) async throws -> Favorite? {
        let snapshot = await loadLibrarySnapshot()
        var favorites = snapshot.favorites

        if let index = favorites.firstIndex(where: { $0.url == url || $0.id == url.absoluteString }) {
            favorites[index].lastMangaURL = chapterURL
            favorites[index].lastChapter = chapterTitle
            favorites[index].lastPage = max(0, pageIndex)
            favorites[index].novelResumePoint = nil
            favorites[index].type = .manga
            return try persistLibrary(favorites: favorites, collections: snapshot.collections).favorites[index]
        }

        guard createIfMissing else { return nil }

        var favorite = Favorite(
            title: chapterTitle,
            url: url,
            lastPage: max(0, pageIndex),
            lastView: 1,
            lastChapter: chapterTitle,
            authorID: nil,
            novelResumePoint: nil,
            isHidden: false,
            type: .manga,
            lastMangaURL: chapterURL
        )
        favorite.parentCollectionID = nil
        favorites.append(favorite)
        return try persistLibrary(favorites: favorites, collections: snapshot.collections).favorites.last ?? favorite
    }

    public func clearAll() async throws {
        _ = try persistLibrary(favorites: [], collections: [])
    }

    private func persistLibrary(
        favorites: [Favorite],
        collections: [FavoriteCollection]
    ) throws -> FavoriteLibrarySnapshot {
        let sanitizedCollections = sanitizeCollectionsForPersistence(collections)
        let validCollectionIDs = Set(sanitizedCollections.map(\.id))
        let sanitizedFavorites = sanitizeFavoritesForPersistence(favorites, validCollectionIDs: validCollectionIDs)

        do {
            let favoritesData = try encoder.encode(sanitizedFavorites)
            let collectionsData = try encoder.encode(sanitizedCollections)
            defaults.set(favoritesData, forKey: key)
            defaults.set(collectionsData, forKey: collectionsKey)
            postChangeNotification()
            return FavoriteLibrarySnapshot(favorites: sanitizedFavorites, collections: sanitizedCollections)
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    private func decodedValue<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func sanitizeLoadedFavorites(
        _ favorites: [Favorite],
        collections: [FavoriteCollection],
        validCollectionIDs: Set<String>
    ) -> [Favorite] {
        let sanitizedFavorites = favorites.map { favorite in
            var favorite = favorite
            if let parentCollectionID = favorite.parentCollectionID, !validCollectionIDs.contains(parentCollectionID) {
                favorite.parentCollectionID = nil
            }
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

        return sanitizeFavoritesForPersistence(sanitizedFavorites, validCollectionIDs: validCollectionIDs)
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
        validCollectionIDs: Set<String>
    ) -> [Favorite] {
        let rootFavorites = favorites
            .filter { favorite in
                favorite.parentCollectionID == nil || !validCollectionIDs.contains(favorite.parentCollectionID ?? "")
            }
            .map { favorite -> Favorite in
                var favorite = favorite
                favorite.parentCollectionID = nil
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
                    favorite.manualOrder = index
                    return favorite
                }
            sanitized.append(contentsOf: collectionFavorites)
        }
        return sanitized
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
