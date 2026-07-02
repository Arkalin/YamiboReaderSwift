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
    public var mangaPageCount: Int?

    public init(lastMangaURL: URL, lastChapter: String, mangaPageIndex: Int, mangaPageCount: Int? = nil) {
        self.lastMangaURL = lastMangaURL
        self.lastChapter = lastChapter
        self.mangaPageIndex = max(0, mangaPageIndex)
        self.mangaPageCount = mangaPageCount.map { max(1, $0) }
    }
}

public struct ReadingProgressRecord: Codable, Hashable, Identifiable, Sendable {
    public var contentTarget: FavoriteContentTarget?
    public var threadURL: URL
    public var kind: ReadingProgressKind
    public var updatedAt: Date
    public var lastReadAt: Date?
    public var novel: NovelReadingProgressRecord?
    public var manga: MangaReadingProgressRecord?

    public var id: String { contentTarget?.id ?? threadURL.absoluteString }

    public init(
        contentTarget: FavoriteContentTarget? = nil,
        threadURL: URL,
        kind: ReadingProgressKind,
        updatedAt: Date = .now,
        lastReadAt: Date? = nil,
        novel: NovelReadingProgressRecord? = nil,
        manga: MangaReadingProgressRecord? = nil
    ) {
        self.contentTarget = contentTarget
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "yamibo.readingProgress.records"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load(for url: URL) async -> ReadingProgressRecord? {
        let canonicalURL = Self.canonicalThreadURL(for: url)
        let key = Self.canonicalURLKey(for: canonicalURL)
        let novelTarget = FavoriteContentTarget(kind: .novelThread, threadURL: canonicalURL)
        let records = recordsByKey()
        return records[key] ?? records[novelTarget.id] ?? records.values.first { Self.canonicalURLKey(for: $0.threadURL) == key }
    }

    public func loadAll() async -> [ReadingProgressRecord] {
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
        var records = recordsByKey()
        let canonicalURL = Self.canonicalThreadURL(for: position.threadURL)
        let target = FavoriteContentTarget(kind: .novelThread, threadURL: canonicalURL)
        let record = ReadingProgressRecord(
            contentTarget: target,
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
        records[target.id] = record
        try persist(records)
        return record
    }

    @discardableResult
    public func saveManga(_ position: MangaProgressReadingPosition, date: Date = .now) async throws -> ReadingProgressRecord {
        if let directoryName = position.directoryName {
            return try await saveMangaTitle(
                cleanBookName: directoryName,
                threadURL: position.threadURL,
                chapterURL: position.chapterURL,
                chapterTitle: position.chapterTitle,
                pageIndex: position.pageIndex,
                pageCount: position.pageCount,
                mangaID: position.mangaID,
                date: date
            )
        }
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
                mangaPageIndex: position.pageIndex,
                mangaPageCount: position.pageCount
            )
        )
        records[key] = record
        try persist(records)
        return record
    }

    @discardableResult
    public func saveMangaTitle(
        cleanBookName: String,
        threadURL: URL? = nil,
        chapterURL: URL,
        chapterTitle: String,
        pageIndex: Int,
        pageCount: Int? = nil,
        mangaID: String? = nil,
        date: Date = .now
    ) async throws -> ReadingProgressRecord {
        var records = recordsByKey()
        let target = FavoriteContentTarget(mangaID: mangaID ?? cleanBookName, mangaCleanBookName: cleanBookName)
        let chapterTID = YamiboThreadURLCanonicalizer.threadID(from: chapterURL)
        let record = ReadingProgressRecord(
            contentTarget: target,
            threadURL: threadURL ?? chapterURL,
            kind: .manga,
            updatedAt: date,
            lastReadAt: date,
            novel: nil,
            manga: MangaReadingProgressRecord(
                lastMangaURL: chapterURL,
                lastChapter: chapterTitle,
                mangaPageIndex: pageIndex,
                mangaPageCount: pageCount
            )
        )
        for candidateID in Self.mangaProgressRetargetCandidateIDs(
            target: target,
            cleanBookName: cleanBookName,
            chapterTID: chapterTID
        ) {
            records.removeValue(forKey: candidateID)
        }
        records[target.id] = record
        try persist(records)
        return record
    }

    public func load(for target: FavoriteContentTarget) async -> ReadingProgressRecord? {
        return recordsByKey()[target.id]
    }

    public func migrateMangaTitleKey(from oldCleanBookName: String, to newCleanBookName: String) async throws {
        var records = recordsByKey()
        let oldTarget = FavoriteContentTarget(mangaCleanBookName: oldCleanBookName)
        let newTarget = FavoriteContentTarget(mangaCleanBookName: newCleanBookName)
        if var record = records.removeValue(forKey: oldTarget.id) {
            record.contentTarget = newTarget
            records[newTarget.id] = record
            try persist(records)
            return
        }
        guard let existing = records.first(where: { _, record in
            record.contentTarget?.mangaCleanBookName == oldCleanBookName
        }) else { return }
        var record = existing.value
        records.removeValue(forKey: existing.key)
        let renamedTarget = record.contentTarget?.renamedMangaTitle(to: newCleanBookName) ?? newTarget
        record.contentTarget = renamedTarget
        records[renamedTarget.id] = record
        try persist(records)
    }

    public func delete(for url: URL) async throws {
        var records = recordsByKey()
        records.removeValue(forKey: Self.canonicalURLKey(for: url))
        try persist(records)
    }

    public func replaceAll(_ records: [ReadingProgressRecord]) async throws {
        var recordsByKey: [String: ReadingProgressRecord] = [:]
        for record in records {
            let normalized = Self.normalizedRecord(record)
            recordsByKey[Self.key(for: normalized)] = normalized
        }
        try persist(recordsByKey)
    }

    public func clearAll() async throws {
        try persist([:])
    }

    private func recordsByKey() -> [String: ReadingProgressRecord] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([ReadingProgressRecord].self, from: data) else {
            return [:]
        }
        var records: [String: ReadingProgressRecord] = [:]
        for record in decoded {
            let normalized = Self.normalizedRecord(record)
            let key = Self.key(for: normalized)
            if let existing = records[key], existing.updatedAt >= normalized.updatedAt {
                continue
            }
            records[key] = normalized
        }
        return records
    }

    private func persist(_ records: [String: ReadingProgressRecord]) throws {
        do {
            let normalized = records
                .values
                .map(Self.normalizedRecord)
                .sorted { $0.id < $1.id }
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
        let canonicalURL = canonicalThreadURL(for: record.threadURL)
        let contentTarget: FavoriteContentTarget?
        if record.kind == .novel {
            contentTarget = record.contentTarget ?? FavoriteContentTarget(kind: .novelThread, threadURL: canonicalURL)
        } else {
            contentTarget = record.contentTarget
        }
        return ReadingProgressRecord(
            contentTarget: contentTarget,
            threadURL: canonicalURL,
            kind: record.kind,
            updatedAt: record.updatedAt,
            lastReadAt: record.lastReadAt,
            novel: record.novel,
            manga: record.manga
        )
    }

    private static func canonicalThreadURL(for url: URL) -> URL {
        FavoriteLibraryURLIdentity.canonicalThreadURL(from: url)
    }

    private static func canonicalURLKey(for url: URL) -> String {
        FavoriteLibraryURLIdentity.canonicalThreadURLKey(for: url)
    }

    private static func key(for record: ReadingProgressRecord) -> String {
        record.contentTarget?.id ?? canonicalURLKey(for: record.threadURL)
    }

    private static func mangaProgressRetargetCandidateIDs(
        target: FavoriteContentTarget,
        cleanBookName: String,
        chapterTID: String?
    ) -> Set<String> {
        guard target.kind == .mangaTitle else { return [] }
        var candidateIDs = Set<String>()
        candidateIDs.insert(FavoriteContentTarget(mangaCleanBookName: cleanBookName).id)
        if let chapterTID = chapterTID?.trimmingCharacters(in: .whitespacesAndNewlines), !chapterTID.isEmpty {
            candidateIDs.insert(FavoriteContentTarget(mangaID: "chapter:\(chapterTID)", mangaCleanBookName: cleanBookName).id)
            candidateIDs.insert(FavoriteContentTarget(mangaID: "thread:\(chapterTID)", mangaCleanBookName: cleanBookName).id)
        }
        candidateIDs.remove(target.id)
        return candidateIDs
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
