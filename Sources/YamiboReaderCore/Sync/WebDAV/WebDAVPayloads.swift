import Foundation

public struct FavoriteLibraryWebDAVPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var updatedAt: Date
    public var accountUID: String?
    public var library: FavoriteLibraryDocument
    public var tombstones: FavoriteLibraryWebDAVTombstones
    public var clocks: FavoriteLibraryWebDAVClocks

    public init(
        version: Int = Self.currentVersion,
        updatedAt: Date,
        accountUID: String? = nil,
        library: FavoriteLibraryDocument,
        tombstones: FavoriteLibraryWebDAVTombstones = FavoriteLibraryWebDAVTombstones(),
        clocks: FavoriteLibraryWebDAVClocks = FavoriteLibraryWebDAVClocks()
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.accountUID = accountUID
        self.library = library
        self.tombstones = tombstones
        self.clocks = clocks
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case updatedAt
        case accountUID
        case library
        case tombstones
        case clocks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try container.decodeIfPresent(Int.self, forKey: .version) else {
            throw WebDAVSyncError.unsupportedPayloadVersion(0)
        }
        guard version == Self.currentVersion else {
            throw WebDAVSyncError.unsupportedPayloadVersion(version)
        }
        self.version = version
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.accountUID = try container.decodeIfPresent(String.self, forKey: .accountUID)
        self.library = try container.decode(FavoriteLibraryDocument.self, forKey: .library)
        self.tombstones = try container.decodeIfPresent(FavoriteLibraryWebDAVTombstones.self, forKey: .tombstones) ?? FavoriteLibraryWebDAVTombstones()
        self.clocks = try container.decodeIfPresent(FavoriteLibraryWebDAVClocks.self, forKey: .clocks) ?? FavoriteLibraryWebDAVClocks()
    }
}

public struct FavoriteLibraryWebDAVTombstones: Codable, Equatable, Sendable {
    public var removedLocationsByTargetID: [String: Set<FavoriteLocation>]
    public var removedTagIDsByTargetID: [String: Set<String>]

    public init(
        removedLocationsByTargetID: [String: Set<FavoriteLocation>] = [:],
        removedTagIDsByTargetID: [String: Set<String>] = [:]
    ) {
        self.removedLocationsByTargetID = removedLocationsByTargetID
        self.removedTagIDsByTargetID = removedTagIDsByTargetID
    }
}

public struct FavoriteLibraryWebDAVClocks: Codable, Equatable, Sendable {
    public var displayNameUpdatedAtByTargetID: [String: Date]
    public var coverUpdatedAtByTargetID: [String: Date]
    public var remoteMappingUpdatedAtByTargetID: [String: Date]

    public init(
        displayNameUpdatedAtByTargetID: [String: Date] = [:],
        coverUpdatedAtByTargetID: [String: Date] = [:],
        remoteMappingUpdatedAtByTargetID: [String: Date] = [:]
    ) {
        self.displayNameUpdatedAtByTargetID = displayNameUpdatedAtByTargetID
        self.coverUpdatedAtByTargetID = coverUpdatedAtByTargetID
        self.remoteMappingUpdatedAtByTargetID = remoteMappingUpdatedAtByTargetID
    }
}

public struct FavoriteLibraryWebDAVMerger: Sendable {
    public init() {}

    public func merge(
        local: FavoriteLibraryWebDAVPayload,
        remote: FavoriteLibraryWebDAVPayload?,
        updatedAt: Date
    ) -> FavoriteLibraryWebDAVPayload {
        guard let remote else {
            var upload = local
            upload.version = FavoriteLibraryWebDAVPayload.currentVersion
            upload.updatedAt = updatedAt
            return upload
        }

        let tombstones = FavoriteLibraryWebDAVTombstones(
            removedLocationsByTargetID: unionSetDictionary(local.tombstones.removedLocationsByTargetID, remote.tombstones.removedLocationsByTargetID),
            removedTagIDsByTargetID: unionSetDictionary(local.tombstones.removedTagIDsByTargetID, remote.tombstones.removedTagIDsByTargetID)
        )
        let clocks = FavoriteLibraryWebDAVClocks(
            displayNameUpdatedAtByTargetID: maxDateDictionary(local.clocks.displayNameUpdatedAtByTargetID, remote.clocks.displayNameUpdatedAtByTargetID),
            coverUpdatedAtByTargetID: maxDateDictionary(local.clocks.coverUpdatedAtByTargetID, remote.clocks.coverUpdatedAtByTargetID),
            remoteMappingUpdatedAtByTargetID: maxDateDictionary(local.clocks.remoteMappingUpdatedAtByTargetID, remote.clocks.remoteMappingUpdatedAtByTargetID)
        )
        let mergedItems = mergeItems(local: local, remote: remote, tombstones: tombstones, clocks: clocks)
        let mergedLibrary = FavoriteLibraryDocument(
            categories: mergeCategories(local.library.categories, remote.library.categories),
            collections: mergeCollections(local.library.collections, remote.library.collections),
            items: mergedItems,
            tags: mergeTags(local.library.tags, remote.library.tags)
        )

        return FavoriteLibraryWebDAVPayload(
            version: FavoriteLibraryWebDAVPayload.currentVersion,
            updatedAt: updatedAt,
            accountUID: local.accountUID ?? remote.accountUID,
            library: mergedLibrary,
            tombstones: tombstones,
            clocks: clocks
        )
    }

    private func mergeItems(
        local: FavoriteLibraryWebDAVPayload,
        remote: FavoriteLibraryWebDAVPayload,
        tombstones: FavoriteLibraryWebDAVTombstones,
        clocks: FavoriteLibraryWebDAVClocks
    ) -> [FavoriteItem] {
        let localByID = Dictionary(uniqueKeysWithValues: local.library.items.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.library.items.map { ($0.id, $0) })
        return Set(localByID.keys).union(remoteByID.keys).compactMap { targetID in
            guard var item = localByID[targetID] ?? remoteByID[targetID] else { return nil }
            if let remoteItem = remoteByID[targetID], localByID[targetID] == nil {
                item = remoteItem
            } else if let localItem = localByID[targetID], let remoteItem = remoteByID[targetID] {
                item.locations = Array(
                    Set(localItem.locations)
                        .union(remoteItem.locations)
                        .subtracting(tombstones.removedLocationsByTargetID[targetID, default: []])
                )
                item.tagIDs = Array(
                    Set(localItem.tagIDs)
                        .union(remoteItem.tagIDs)
                        .subtracting(tombstones.removedTagIDsByTargetID[targetID, default: []])
                ).sorted()
                item.displayName = choose(
                    local: localItem.displayName,
                    remote: remoteItem.displayName,
                    localDate: local.clocks.displayNameUpdatedAtByTargetID[targetID],
                    remoteDate: remote.clocks.displayNameUpdatedAtByTargetID[targetID]
                )
                item.coverURL = choose(
                    local: localItem.coverURL,
                    remote: remoteItem.coverURL,
                    localDate: local.clocks.coverUpdatedAtByTargetID[targetID],
                    remoteDate: remote.clocks.coverUpdatedAtByTargetID[targetID]
                )
                item.contentUpdatedAt = maxDate(localItem.contentUpdatedAt, remoteItem.contentUpdatedAt)
                item.forumID = localItem.forumID ?? remoteItem.forumID
                item.forumName = localItem.forumName ?? remoteItem.forumName
                item.remoteMapping = choose(
                    local: localItem.remoteMapping,
                    remote: remoteItem.remoteMapping,
                    localDate: local.clocks.remoteMappingUpdatedAtByTargetID[targetID],
                    remoteDate: remote.clocks.remoteMappingUpdatedAtByTargetID[targetID]
                )
                item.updatedAt = max(localItem.updatedAt, remoteItem.updatedAt)
            }
            return item.locations.isEmpty ? nil : item
        }
        .sorted { $0.id < $1.id }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func mergeCategories(_ local: [FavoriteCategory], _ remote: [FavoriteCategory]) -> [FavoriteCategory] {
        keyedByID(local + remote)
            .sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                if $0.manualOrder != $1.manualOrder { return $0.manualOrder < $1.manualOrder }
                return $0.id < $1.id
            }
    }

    private func mergeCollections(_ local: [LocalFavoriteCollection], _ remote: [LocalFavoriteCollection]) -> [LocalFavoriteCollection] {
        keyedByID(local + remote)
            .sorted {
                if $0.categoryID != $1.categoryID { return $0.categoryID < $1.categoryID }
                if $0.manualOrder != $1.manualOrder { return $0.manualOrder < $1.manualOrder }
                return $0.id < $1.id
            }
    }

    private func mergeTags(_ local: [FavoriteTag], _ remote: [FavoriteTag]) -> [FavoriteTag] {
        keyedByID(local + remote)
            .sorted {
                if $0.manualOrder != $1.manualOrder { return $0.manualOrder < $1.manualOrder }
                return $0.id < $1.id
            }
    }
}

public struct ReadingProgressWebDAVPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var updatedAt: Date
    public var records: [ReadingProgressRecord]

    public init(version: Int = Self.currentVersion, updatedAt: Date, records: [ReadingProgressRecord]) {
        self.version = version
        self.updatedAt = updatedAt
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case updatedAt
        case records
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try container.decodeIfPresent(Int.self, forKey: .version) else {
            throw WebDAVSyncError.unsupportedPayloadVersion(0)
        }
        guard version == Self.currentVersion else {
            throw WebDAVSyncError.unsupportedPayloadVersion(version)
        }
        self.version = version
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.records = try container.decode([ReadingProgressWebDAVRecord].self, forKey: .records)
            .map { $0.record }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(records.map(ReadingProgressWebDAVRecord.init(record:)), forKey: .records)
    }
}

public struct ReadingProgressWebDAVMerger: Sendable {
    public init() {}

    public func merge(
        local: ReadingProgressWebDAVPayload,
        remote: ReadingProgressWebDAVPayload?,
        updatedAt: Date
    ) -> ReadingProgressWebDAVPayload {
        guard let remote else {
            return ReadingProgressWebDAVPayload(version: ReadingProgressWebDAVPayload.currentVersion, updatedAt: updatedAt, records: local.records)
        }
        var byID = Dictionary(uniqueKeysWithValues: local.records.map { ($0.id, $0) })
        for record in remote.records {
            if let existing = byID[record.id], existing.updatedAt >= record.updatedAt {
                continue
            }
            byID[record.id] = record
        }
        return ReadingProgressWebDAVPayload(
            version: ReadingProgressWebDAVPayload.currentVersion,
            updatedAt: updatedAt,
            records: byID.values.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
        )
    }
}

public struct AppSettingsWebDAVPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var updatedAt: Date
    public var accountUID: String?
    public var appSettings: WebDAVSyncedAppSettings

    public init(
        version: Int = Self.currentVersion,
        updatedAt: Date,
        accountUID: String? = nil,
        appSettings: WebDAVSyncedAppSettings
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.accountUID = accountUID
        self.appSettings = appSettings
    }
}

private func unionSetDictionary<Value: Hashable>(
    _ lhs: [String: Set<Value>],
    _ rhs: [String: Set<Value>]
) -> [String: Set<Value>] {
    var result = lhs
    for (key, values) in rhs {
        result[key, default: []].formUnion(values)
    }
    return result
}

private func maxDateDictionary(_ lhs: [String: Date], _ rhs: [String: Date]) -> [String: Date] {
    var result = lhs
    for (key, value) in rhs {
        if let existing = result[key], existing >= value {
            continue
        }
        result[key] = value
    }
    return result
}

private func keyedByID<Value: Identifiable>(_ values: [Value]) -> [Value] where Value.ID == String {
    var byID: [String: Value] = [:]
    for value in values {
        byID[value.id] = value
    }
    return Array(byID.values)
}

private struct ReadingProgressWebDAVRecord: Codable, Equatable, Sendable {
    var contentTarget: FavoriteContentTarget
    var kind: ReadingProgressKind
    var updatedAt: Date
    var lastReadAt: Date?
    var threadID: String?
    var novel: NovelReadingProgressRecord?
    var manga: MangaReadingProgressWebDAVRecord?

    init(record: ReadingProgressRecord) {
        self.contentTarget = record.contentTarget ?? Self.fallbackTarget(for: record)
        self.kind = record.kind
        self.updatedAt = record.updatedAt
        self.lastReadAt = record.lastReadAt
        self.threadID = record.threadID
        self.novel = record.novel
        if let manga = record.manga {
            self.manga = MangaReadingProgressWebDAVRecord(
                chapterThreadID: manga.chapterThreadID ?? YamiboThreadURLCanonicalizer.threadID(from: manga.lastMangaURL),
                lastChapter: manga.lastChapter,
                mangaPageIndex: manga.mangaPageIndex,
                mangaPageCount: manga.mangaPageCount
            )
        } else {
            self.manga = nil
        }
    }

    var record: ReadingProgressRecord {
        let threadURL = contentTarget.canonicalURL
            ?? Self.threadURL(for: threadID)
            ?? Self.threadURL(for: manga?.chapterThreadID)
            ?? URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=0")!
        return ReadingProgressRecord(
            contentTarget: contentTarget,
            threadURL: threadURL,
            kind: kind,
            updatedAt: updatedAt,
            lastReadAt: lastReadAt,
            novel: novel,
            manga: manga.map { payload in
                MangaReadingProgressRecord(
                    lastMangaURL: Self.threadURL(for: payload.chapterThreadID) ?? threadURL,
                    chapterThreadID: payload.chapterThreadID,
                    lastChapter: payload.lastChapter,
                    mangaPageIndex: payload.mangaPageIndex,
                    mangaPageCount: payload.mangaPageCount
                )
            }
        )
    }

    private static func fallbackTarget(for record: ReadingProgressRecord) -> FavoriteContentTarget {
        if record.kind == .novel {
            return FavoriteContentTarget(kind: .novelThread, threadURL: record.threadURL)
        }
        let threadID = record.threadID
            ?? record.manga?.chapterThreadID
            ?? record.manga.flatMap { YamiboThreadURLCanonicalizer.threadID(from: $0.lastMangaURL) }
            ?? record.threadURL.absoluteString
        return FavoriteContentTarget(
            mangaID: "thread:\(threadID)",
            mangaCleanBookName: record.manga?.lastChapter ?? threadID
        )
    }

    private static func threadURL(for threadID: String?) -> URL? {
        let trimmed = threadID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return FavoriteLibraryURLIdentity.canonicalThreadURL(
            from: YamiboRoute.threadByID(tid: trimmed, page: 1, authorID: nil, reverse: false).url
        )
    }
}

private struct MangaReadingProgressWebDAVRecord: Codable, Equatable, Sendable {
    var chapterThreadID: String?
    var lastChapter: String
    var mangaPageIndex: Int
    var mangaPageCount: Int?
}

private func choose<Value>(
    local: Value?,
    remote: Value?,
    localDate: Date?,
    remoteDate: Date?
) -> Value? {
    guard localDate != remoteDate else { return local ?? remote }
    if let remoteDate, localDate == nil || remoteDate > localDate! {
        return remote
    }
    return local
}
