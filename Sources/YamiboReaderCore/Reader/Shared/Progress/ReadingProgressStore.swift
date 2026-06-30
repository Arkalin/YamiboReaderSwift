import Foundation

public enum ReadingProgressKind: String, Codable, Hashable, Sendable {
    case novel
    case manga
}

public struct NovelReadingProgressRecord: Codable, Hashable, Sendable {
    public var lastView: Int
    public var lastChapter: String?
    public var authorID: String?
    public var novelResumePoint: ReaderResumePoint?
    public var novelMaxView: Int?
    public var novelDocumentSurfaceProgressPercent: Int?
    public var threadCoverURL: URL?

    public init(
        lastView: Int = 1,
        lastChapter: String? = nil,
        authorID: String? = nil,
        novelResumePoint: ReaderResumePoint? = nil,
        novelMaxView: Int? = nil,
        novelDocumentSurfaceProgressPercent: Int? = nil,
        threadCoverURL: URL? = nil
    ) {
        let resolvedView = max(1, novelResumePoint?.view ?? lastView)
        self.lastView = resolvedView
        self.lastChapter = novelResumePoint?.chapterTitle ?? lastChapter
        self.authorID = novelResumePoint?.authorID ?? authorID
        self.novelResumePoint = novelResumePoint
        self.novelMaxView = novelMaxView.map { max(resolvedView, $0) }
        self.novelDocumentSurfaceProgressPercent = novelDocumentSurfaceProgressPercent.map { min(max($0, 0), 100) }
        self.threadCoverURL = threadCoverURL
    }
}

public struct MangaReadingProgressRecord: Codable, Hashable, Sendable {
    public var lastMangaURL: URL
    public var lastChapter: String
    public var mangaPageIndex: Int

    public init(lastMangaURL: URL, lastChapter: String, mangaPageIndex: Int) {
        self.lastMangaURL = lastMangaURL
        self.lastChapter = lastChapter
        self.mangaPageIndex = max(0, mangaPageIndex)
    }
}

public struct ReadingProgressRecord: Codable, Hashable, Identifiable, Sendable {
    public var threadURL: URL
    public var kind: ReadingProgressKind
    public var updatedAt: Date
    public var lastReadAt: Date?
    public var novel: NovelReadingProgressRecord?
    public var manga: MangaReadingProgressRecord?

    public var id: String { threadURL.absoluteString }

    public init(
        threadURL: URL,
        kind: ReadingProgressKind,
        updatedAt: Date = .now,
        lastReadAt: Date? = nil,
        novel: NovelReadingProgressRecord? = nil,
        manga: MangaReadingProgressRecord? = nil
    ) {
        self.threadURL = FavoriteLibraryURLIdentity.canonicalThreadURL(from: threadURL)
        self.kind = kind
        self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
        self.novel = novel
        self.manga = manga
    }
}

public actor ReadingProgressStore {
    public static let didChangeNotification = Notification.Name("yamibo.readingProgressStore.didChange")
    public static let changeIDUserInfoKey = "changeID"

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let migratedFromFavoritesKey: String
    private let favoriteStore: (any FavoriteStoring)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "yamibo.readingProgress.records",
        migratedFromFavoritesKey: String = "yamibo.readingProgress.migratedFromFavorites",
        favoriteStore: (any FavoriteStoring)? = nil
    ) {
        self.defaults = defaults
        self.key = key
        self.migratedFromFavoritesKey = migratedFromFavoritesKey
        self.favoriteStore = favoriteStore
    }

    public func migrateFromFavoritesIfNeeded() async {
        await ensureMigrated()
    }

    public func load(for url: URL) async -> ReadingProgressRecord? {
        await ensureMigrated()
        return recordsByKey()[Self.canonicalURLKey(for: url)]
    }

    public func loadAll() async -> [ReadingProgressRecord] {
        await ensureMigrated()
        return recordsByKey()
            .values
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.threadURL.absoluteString < rhs.threadURL.absoluteString
            }
    }

    @discardableResult
    public func saveNovel(_ position: NovelReadingPosition, date: Date = .now) async throws -> ReadingProgressRecord {
        await ensureMigrated()
        var records = recordsByKey()
        let canonicalURL = Self.canonicalThreadURL(for: position.threadURL)
        let key = Self.canonicalURLKey(for: canonicalURL)
        let record = ReadingProgressRecord(
            threadURL: canonicalURL,
            kind: .novel,
            updatedAt: date,
            lastReadAt: date,
            novel: NovelReadingProgressRecord(
                lastView: position.view,
                lastChapter: position.chapterTitle,
                authorID: position.authorID,
                novelResumePoint: position.resumePoint,
                novelMaxView: position.maxView,
                novelDocumentSurfaceProgressPercent: position.documentSurfaceProgressPercent,
                threadCoverURL: position.threadCoverURL
            ),
            manga: nil
        )
        records[key] = record
        try persist(records)
        return record
    }

    @discardableResult
    public func saveManga(_ position: MangaProgressReadingPosition, date: Date = .now) async throws -> ReadingProgressRecord {
        await ensureMigrated()
        var records = recordsByKey()
        let canonicalURL = Self.canonicalThreadURL(for: position.threadURL)
        let key = Self.canonicalURLKey(for: canonicalURL)
        let record = ReadingProgressRecord(
            threadURL: canonicalURL,
            kind: .manga,
            updatedAt: date,
            lastReadAt: date,
            novel: nil,
            manga: MangaReadingProgressRecord(
                lastMangaURL: position.chapterURL,
                lastChapter: position.chapterTitle,
                mangaPageIndex: position.pageIndex
            )
        )
        records[key] = record
        try persist(records)
        return record
    }

    @discardableResult
    public func saveFavoriteLegacyProgress(_ favorite: Favorite, date: Date = .now) async throws -> ReadingProgressRecord? {
        await ensureMigrated()
        guard let record = Self.record(from: favorite, date: date) else { return nil }
        var records = recordsByKey()
        let key = Self.canonicalURLKey(for: record.threadURL)
        if let existing = records[key] {
            return existing
        }
        records[key] = record
        try persist(records)
        return record
    }

    public func delete(for url: URL) async throws {
        await ensureMigrated()
        var records = recordsByKey()
        records.removeValue(forKey: Self.canonicalURLKey(for: url))
        try persist(records)
    }

    public func clearAll() async throws {
        try persist([:])
        defaults.removeObject(forKey: migratedFromFavoritesKey)
    }

    private func ensureMigrated() async {
        guard !defaults.bool(forKey: migratedFromFavoritesKey) else { return }
        defer { defaults.set(true, forKey: migratedFromFavoritesKey) }
        guard let favoriteStore else { return }

        let snapshot = await favoriteStore.loadLibrarySnapshot()
        var records = recordsByKey()
        for archive in snapshot.archivedMetadata {
            guard let record = Self.record(from: archive) else { continue }
            let key = Self.canonicalURLKey(for: record.threadURL)
            if records[key] == nil {
                records[key] = record
            }
        }
        for favorite in snapshot.favorites {
            guard let record = Self.record(from: favorite) else { continue }
            records[Self.canonicalURLKey(for: record.threadURL)] = record
        }
        try? persist(records)
    }

    private func recordsByKey() -> [String: ReadingProgressRecord] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([ReadingProgressRecord].self, from: data) else {
            return [:]
        }
        var records: [String: ReadingProgressRecord] = [:]
        for record in decoded {
            let normalized = Self.normalizedRecord(record)
            records[Self.canonicalURLKey(for: normalized.threadURL)] = normalized
        }
        return records
    }

    private func persist(_ records: [String: ReadingProgressRecord]) throws {
        do {
            let normalized = records
                .values
                .map(Self.normalizedRecord)
                .sorted { $0.threadURL.absoluteString < $1.threadURL.absoluteString }
            defaults.set(try encoder.encode(normalized), forKey: key)
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }

    private static func normalizedRecord(_ record: ReadingProgressRecord) -> ReadingProgressRecord {
        ReadingProgressRecord(
            threadURL: record.threadURL,
            kind: record.kind,
            updatedAt: record.updatedAt,
            lastReadAt: record.lastReadAt,
            novel: record.novel,
            manga: record.manga
        )
    }

    private static func record(from favorite: Favorite, date: Date = .now) -> ReadingProgressRecord? {
        record(
            threadURL: favorite.url,
            type: favorite.type,
            mangaPageIndex: favorite.mangaPageIndex,
            lastView: favorite.lastView,
            lastChapter: favorite.lastChapter,
            authorID: favorite.authorID,
            novelResumePoint: favorite.novelResumePoint,
            novelMaxView: favorite.novelMaxView,
            novelDocumentSurfaceProgressPercent: favorite.novelDocumentSurfaceProgressPercent,
            lastMangaURL: favorite.lastMangaURL,
            lastReadAt: favorite.lastReadAt,
            date: date
        )
    }

    private static func record(from archive: FavoriteMetadataArchiveEntry, date: Date = .now) -> ReadingProgressRecord? {
        record(
            threadURL: archive.canonicalThreadURL,
            type: archive.type,
            mangaPageIndex: archive.mangaPageIndex,
            lastView: archive.lastView,
            lastChapter: archive.lastChapter,
            authorID: archive.authorID,
            novelResumePoint: archive.novelResumePoint,
            novelMaxView: archive.novelMaxView,
            novelDocumentSurfaceProgressPercent: archive.novelDocumentSurfaceProgressPercent,
            lastMangaURL: archive.lastMangaURL,
            lastReadAt: archive.lastReadAt,
            date: date
        )
    }

    private static func record(
        threadURL: URL,
        type: FavoriteType,
        mangaPageIndex: Int,
        lastView: Int,
        lastChapter: String?,
        authorID: String?,
        novelResumePoint: ReaderResumePoint?,
        novelMaxView: Int?,
        novelDocumentSurfaceProgressPercent: Int?,
        lastMangaURL: URL?,
        lastReadAt: Date?,
        date: Date
    ) -> ReadingProgressRecord? {
        let hasNovelProgress = novelResumePoint != nil ||
            lastView > 1 ||
            trimmedNonEmpty(lastChapter) != nil ||
            trimmedNonEmpty(authorID) != nil ||
            novelMaxView != nil ||
            novelDocumentSurfaceProgressPercent != nil
        let hasMangaProgress = lastMangaURL != nil || mangaPageIndex > 0

        if type == .manga || (!hasNovelProgress && hasMangaProgress) {
            guard let lastMangaURL else { return nil }
            return ReadingProgressRecord(
                threadURL: threadURL,
                kind: .manga,
                updatedAt: lastReadAt ?? date,
                lastReadAt: lastReadAt,
                novel: nil,
                manga: MangaReadingProgressRecord(
                    lastMangaURL: lastMangaURL,
                    lastChapter: lastChapter ?? "",
                    mangaPageIndex: mangaPageIndex
                )
            )
        }

        guard hasNovelProgress else { return nil }
        return ReadingProgressRecord(
            threadURL: threadURL,
            kind: .novel,
            updatedAt: lastReadAt ?? date,
            lastReadAt: lastReadAt,
            novel: NovelReadingProgressRecord(
                lastView: lastView,
                lastChapter: lastChapter,
                authorID: authorID,
                novelResumePoint: novelResumePoint,
                novelMaxView: novelMaxView,
                novelDocumentSurfaceProgressPercent: novelDocumentSurfaceProgressPercent
            ),
            manga: nil
        )
    }

    private static func canonicalThreadURL(for url: URL) -> URL {
        FavoriteLibraryURLIdentity.canonicalThreadURL(from: url)
    }

    private static func canonicalURLKey(for url: URL) -> String {
        FavoriteLibraryURLIdentity.canonicalThreadURLKey(for: url)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
