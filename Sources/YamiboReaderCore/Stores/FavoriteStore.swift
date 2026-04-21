import Foundation

public protocol FavoriteStoring: Sendable {
    func loadFavorites() async -> [Favorite]
    func saveFavorites(_ favorites: [Favorite]) async throws
    func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite]
    func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite]
    func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite]
    func setDisplayName(_ displayName: String?, for favoriteID: String) async throws -> [Favorite]
    func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite]
    func deleteFavorite(id: String) async throws -> [Favorite]
    func favorite(for url: URL) async -> Favorite?
    func favorite(id: String) async -> Favorite?
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.favorites") {
        self.defaults = defaults
        self.key = key
    }

    public func loadFavorites() async -> [Favorite] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? decoder.decode([Favorite].self, from: data)) ?? []
    }

    public func saveFavorites(_ favorites: [Favorite]) async throws {
        do {
            let data = try encoder.encode(favorites)
            defaults.set(data, forKey: key)
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite] {
        let local = await loadFavorites()
        let localIDs = Set(local.map(\.id))
        let remoteByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        let remoteNewFavorites = favorites.filter { !localIDs.contains($0.id) }
        var merged = remoteNewFavorites

        for localFavorite in local {
            if let remoteFavorite = remoteByID[localFavorite.id] {
                var updated = localFavorite
                updated.title = remoteFavorite.title
                updated.url = remoteFavorite.url
                updated.remoteFavoriteID = remoteFavorite.remoteFavoriteID ?? updated.remoteFavoriteID
                if updated.type == .unknown {
                    updated.type = remoteFavorite.type
                }
                merged.append(updated)
            } else if localFavorite.isHidden {
                merged.append(localFavorite)
            }
        }

        try await saveFavorites(merged)
        return merged
    }

    public func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async throws -> [Favorite] {
        guard !visibleIDs.isEmpty, !fromOffsets.isEmpty else {
            return await loadFavorites()
        }

        let favorites = await loadFavorites()
        let favoritesByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        var visibleFavorites = visibleIDs.compactMap { favoritesByID[$0] }
        guard visibleFavorites.count > 1 else { return favorites }

        visibleFavorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let visibleSet = Set(visibleIDs)
        var reorderedIterator = visibleFavorites.makeIterator()
        let updated = favorites.map { favorite in
            guard visibleSet.contains(favorite.id) else { return favorite }
            return reorderedIterator.next() ?? favorite
        }

        try await saveFavorites(updated)
        return updated
    }

    public func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite] {
        let updated = await updateFavorites { favorite in
            favorite.isHidden = isHidden
        } matching: { favorite in
            favorite.id == favoriteID
        }
        try await saveFavorites(updated)
        return updated
    }

    public func setDisplayName(_ displayName: String?, for favoriteID: String) async throws -> [Favorite] {
        let normalized = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let updated = await updateFavorites { favorite in
            favorite.displayName = normalized
        } matching: { favorite in
            favorite.id == favoriteID
        }
        try await saveFavorites(updated)
        return updated
    }

    public func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite] {
        let updated = await updateFavorites { favorite in
            favorite.type = type
        } matching: { favorite in
            favorite.id == favoriteID
        }
        try await saveFavorites(updated)
        return updated
    }

    public func deleteFavorite(id favoriteID: String) async throws -> [Favorite] {
        let updated = await loadFavorites().filter { $0.id != favoriteID }
        try await saveFavorites(updated)
        return updated
    }

    public func favorite(for url: URL) async -> Favorite? {
        await loadFavorites().first { favorite in
            favorite.url == url || favorite.id == url.absoluteString
        }
    }

    public func favorite(id: String) async -> Favorite? {
        await loadFavorites().first { $0.id == id }
    }

    public func updateReadingProgress(for url: URL, progress: ReaderProgress) async throws -> Favorite {
        var favorites = await loadFavorites()
        if let index = favorites.firstIndex(where: { $0.url == url || $0.id == url.absoluteString }) {
            favorites[index].lastView = progress.view
            favorites[index].lastPage = progress.page
            favorites[index].lastChapter = progress.chapterTitle
            favorites[index].authorID = progress.authorID
            favorites[index].novelResumePoint = progress.resumePoint
            if favorites[index].type == .unknown {
                favorites[index].type = .novel
            }
            try await saveFavorites(favorites)
            return favorites[index]
        }

        let favorite = Favorite(
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
        favorites.append(favorite)
        try await saveFavorites(favorites)
        return favorite
    }

    public func updateMangaProgress(for url: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int) async throws -> Favorite {
        var favorites = await loadFavorites()
        if let index = favorites.firstIndex(where: { $0.url == url || $0.id == url.absoluteString }) {
            favorites[index].lastMangaURL = chapterURL
            favorites[index].lastChapter = chapterTitle
            favorites[index].lastPage = max(0, pageIndex)
            favorites[index].novelResumePoint = nil
            favorites[index].type = .manga
            try await saveFavorites(favorites)
            return favorites[index]
        }

        let favorite = Favorite(
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
        favorites.append(favorite)
        try await saveFavorites(favorites)
        return favorite
    }

    public func clearAll() async throws {
        try await saveFavorites([])
    }

    private func updateFavorites(
        _ update: (inout Favorite) -> Void,
        matching predicate: (Favorite) -> Bool
    ) async -> [Favorite] {
        await loadFavorites().map { favorite in
            guard predicate(favorite) else { return favorite }
            var favorite = favorite
            update(&favorite)
            return favorite
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
