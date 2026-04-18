import Foundation

public protocol FavoriteStoring: Sendable {
    func loadFavorites() async -> [Favorite]
    func saveFavorites(_ favorites: [Favorite]) async throws
    func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite]
    func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite]
    func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite]
    func favorite(for url: URL) async -> Favorite?
    func updateReadingProgress(for url: URL, progress: ReaderProgress) async throws -> Favorite
}

public actor FavoriteStore: FavoriteStoring {
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
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func mergeRemoteFavorites(_ favorites: [Favorite]) async throws -> [Favorite] {
        let local = await loadFavorites()
        var localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var merged: [Favorite] = []

        for remote in favorites {
            if var existing = localByID.removeValue(forKey: remote.id) {
                existing.title = remote.title
                existing.url = remote.url
                if existing.type == .unknown {
                    existing.type = remote.type
                }
                merged.append(existing)
            } else {
                merged.append(remote)
            }
        }

        let hiddenOrLocalOnly = localByID.values.filter(\.isHidden)
        merged.append(contentsOf: hiddenOrLocalOnly)
        try await saveFavorites(merged)
        return merged
    }

    public func setHidden(_ isHidden: Bool, for favoriteID: String) async throws -> [Favorite] {
        let updated = await loadFavorites().map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.isHidden = isHidden
            return favorite
        }
        try await saveFavorites(updated)
        return updated
    }

    public func setType(_ type: FavoriteType, for favoriteID: String) async throws -> [Favorite] {
        let updated = await loadFavorites().map { favorite in
            guard favorite.id == favoriteID else { return favorite }
            var favorite = favorite
            favorite.type = type
            return favorite
        }
        try await saveFavorites(updated)
        return updated
    }

    public func favorite(for url: URL) async -> Favorite? {
        await loadFavorites().first { favorite in
            favorite.url == url || favorite.id == url.absoluteString
        }
    }

    public func updateReadingProgress(for url: URL, progress: ReaderProgress) async throws -> Favorite {
        var favorites = await loadFavorites()
        if let index = favorites.firstIndex(where: { $0.url == url || $0.id == url.absoluteString }) {
            favorites[index].lastView = progress.view
            favorites[index].lastPage = progress.page
            favorites[index].lastChapter = progress.chapterTitle
            favorites[index].authorID = progress.authorID
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
            isHidden: false,
            type: .novel
        )
        favorites.append(favorite)
        try await saveFavorites(favorites)
        return favorite
    }
}
