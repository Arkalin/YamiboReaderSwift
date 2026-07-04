import Foundation

public enum FavoriteContentTargetKind: String, Codable, CaseIterable, Sendable {
    case normalThread
    case novelThread
    case mangaTitle
}

public enum FavoriteContentTarget: Codable, Hashable, Identifiable, Sendable {
    case normalThread(threadID: String)
    case novelThread(threadID: String)
    case mangaTitle(mangaID: String, cleanBookName: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case threadID
        case mangaID
        case cleanBookName
    }

    public var id: String {
        switch self {
        case let .normalThread(threadID):
            "thread:normal:\(threadID)"
        case let .novelThread(threadID):
            "thread:novel:\(threadID)"
        case let .mangaTitle(mangaID, _):
            "manga-title:\(mangaID)"
        }
    }

    public var kind: FavoriteContentTargetKind {
        switch self {
        case .normalThread:
            .normalThread
        case .novelThread:
            .novelThread
        case .mangaTitle:
            .mangaTitle
        }
    }

    public var mangaID: String? {
        guard case let .mangaTitle(mangaID, _) = self else { return nil }
        return mangaID
    }

    public var mangaCleanBookName: String? {
        guard case let .mangaTitle(_, cleanBookName) = self else { return nil }
        return cleanBookName
    }

    public var threadID: String? {
        switch self {
        case let .normalThread(threadID), let .novelThread(threadID):
            threadID
        case .mangaTitle:
            nil
        }
    }

    public init(kind: FavoriteContentTargetKind, threadID: String) {
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedThreadID.isEmpty, "FavoriteContentTarget requires a Yamibo thread tid")
        switch kind {
        case .normalThread:
            self = .normalThread(threadID: normalizedThreadID)
        case .novelThread:
            self = .novelThread(threadID: normalizedThreadID)
        case .mangaTitle:
            self = .mangaTitle(mangaID: normalizedThreadID, cleanBookName: normalizedThreadID)
        }
    }

    public init(mangaCleanBookName: String) {
        let normalizedName = mangaCleanBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        self = .mangaTitle(mangaID: normalizedName, cleanBookName: normalizedName)
    }

    public init(mangaID: String, mangaCleanBookName: String) {
        let normalizedName = mangaCleanBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = mangaID.trimmingCharacters(in: .whitespacesAndNewlines)
        self = .mangaTitle(
            mangaID: normalizedID.isEmpty ? normalizedName : normalizedID,
            cleanBookName: normalizedName
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(FavoriteContentTargetKind.self, forKey: .kind)
        switch kind {
        case .normalThread:
            self = .normalThread(threadID: try Self.decodeThreadID(from: container))
        case .novelThread:
            self = .novelThread(threadID: try Self.decodeThreadID(from: container))
        case .mangaTitle:
            let cleanBookName = try container.decode(String.self, forKey: .cleanBookName)
            self = .mangaTitle(
                mangaID: try container.decodeIfPresent(String.self, forKey: .mangaID) ?? cleanBookName,
                cleanBookName: cleanBookName
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .normalThread(threadID), let .novelThread(threadID):
            try container.encode(threadID, forKey: .threadID)
        case let .mangaTitle(mangaID, cleanBookName):
            try container.encode(mangaID, forKey: .mangaID)
            try container.encode(cleanBookName, forKey: .cleanBookName)
        }
    }

    public func renamedMangaTitle(to cleanBookName: String) -> FavoriteContentTarget {
        guard case let .mangaTitle(mangaID, _) = self else { return self }
        return FavoriteContentTarget(mangaID: mangaID, mangaCleanBookName: cleanBookName)
    }

    private static func decodeThreadID(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        if let threadID = try container.decodeIfPresent(String.self, forKey: .threadID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !threadID.isEmpty {
            return threadID
        }
        throw DecodingError.keyNotFound(
            CodingKeys.threadID,
            DecodingError.Context(codingPath: container.codingPath, debugDescription: "FavoriteContentTarget requires threadID")
        )
    }
}

public enum FavoriteSourceGroup: Codable, Hashable, Sendable {
    case forumBoard(id: String, label: String)
    case mangaTitle(mangaID: String, cleanBookName: String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case forumBoard
        case mangaTitle
        case unknown
    }

    private enum ForumBoardCodingKeys: String, CodingKey {
        case id
        case label
    }

    private enum MangaTitleCodingKeys: String, CodingKey {
        case mangaID
        case cleanBookName
    }

    public static func == (lhs: FavoriteSourceGroup, rhs: FavoriteSourceGroup) -> Bool {
        switch (lhs, rhs) {
        case let (.forumBoard(lhsID, _), .forumBoard(rhsID, _)):
            lhsID == rhsID
        case let (.mangaTitle(lhsID, _), .mangaTitle(rhsID, _)):
            lhsID == rhsID
        case (.unknown, .unknown):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .forumBoard(id, _):
            hasher.combine("forumBoard")
            hasher.combine(id)
        case let .mangaTitle(mangaID, _):
            hasher.combine("mangaTitle")
            hasher.combine(mangaID)
        case .unknown:
            hasher.combine("unknown")
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.unknown) {
            self = .unknown
            return
        }
        if container.contains(.forumBoard) {
            let values = try container.nestedContainer(keyedBy: ForumBoardCodingKeys.self, forKey: .forumBoard)
            self = .forumBoard(
                id: try values.decode(String.self, forKey: .id),
                label: try values.decode(String.self, forKey: .label)
            )
            return
        }
        let values = try container.nestedContainer(keyedBy: MangaTitleCodingKeys.self, forKey: .mangaTitle)
        let cleanBookName = try values.decode(String.self, forKey: .cleanBookName)
        self = FavoriteSourceGroup.mangaTitle(
            mangaID: try values.decodeIfPresent(String.self, forKey: .mangaID) ?? cleanBookName,
            cleanBookName: cleanBookName
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .forumBoard(id, label):
            var values = container.nestedContainer(keyedBy: ForumBoardCodingKeys.self, forKey: .forumBoard)
            try values.encode(id, forKey: .id)
            try values.encode(label, forKey: .label)
        case let .mangaTitle(mangaID, cleanBookName):
            var values = container.nestedContainer(keyedBy: MangaTitleCodingKeys.self, forKey: .mangaTitle)
            try values.encode(mangaID, forKey: .mangaID)
            try values.encode(cleanBookName, forKey: .cleanBookName)
        case .unknown:
            _ = container.nestedContainer(keyedBy: MangaTitleCodingKeys.self, forKey: .unknown)
        }
    }

    public var forumID: String? {
        guard case let .forumBoard(id, _) = self else { return nil }
        return id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var forumName: String? {
        guard case let .forumBoard(_, label) = self else { return nil }
        return label.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func normalizedForumMetadata(
        sourceGroup: FavoriteSourceGroup,
        forumID: String?,
        forumName: String?
    ) -> (sourceGroup: FavoriteSourceGroup, forumID: String?, forumName: String?) {
        let trimmedForumID = forumID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedForumName = forumName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch sourceGroup {
        case let .forumBoard(id, label):
            let resolvedID = trimmedForumID ?? id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let resolvedName = trimmedForumName ?? label.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            guard let resolvedID else {
                return (.unknown, nil, nil)
            }
            return (.forumBoard(id: resolvedID, label: resolvedName ?? resolvedID), resolvedID, resolvedName)
        case let .mangaTitle(mangaID, cleanBookName):
            return (.mangaTitle(mangaID: mangaID, cleanBookName: cleanBookName), nil, nil)
        case .unknown:
            guard let trimmedForumID else {
                return (.unknown, nil, nil)
            }
            return (.forumBoard(id: trimmedForumID, label: trimmedForumName ?? trimmedForumID), trimmedForumID, trimmedForumName)
        }
    }
}

public extension FavoriteSourceGroup {
    static func mangaTitle(cleanBookName: String) -> FavoriteSourceGroup {
        let normalizedName = cleanBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        return .mangaTitle(mangaID: normalizedName, cleanBookName: normalizedName)
    }
}

public enum FavoriteLocation: Codable, Hashable, Identifiable, Sendable {
    case category(String)
    case collection(categoryID: String, collectionID: String)

    public var id: String {
        switch self {
        case let .category(categoryID):
            "category:\(categoryID)"
        case let .collection(categoryID, collectionID):
            "category:\(categoryID):collection:\(collectionID)"
        }
    }

    public var categoryID: String {
        switch self {
        case let .category(categoryID), let .collection(categoryID, _):
            categoryID
        }
    }

    public var collectionID: String? {
        if case let .collection(_, collectionID) = self {
            return collectionID
        }
        return nil
    }
}

public struct FavoriteCategory: Codable, Hashable, Identifiable, Sendable {
    public static let defaultID = "default"
    public static let defaultStorageName = "default"

    public let id: String
    public var name: String
    public var manualOrder: Int
    public var isDefault: Bool

    public init(id: String = UUID().uuidString, name: String, manualOrder: Int = 0, isDefault: Bool = false) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.manualOrder = manualOrder
        self.isDefault = isDefault
    }

    public static var defaultCategory: FavoriteCategory {
        FavoriteCategory(id: defaultID, name: defaultStorageName, manualOrder: 0, isDefault: true)
    }

    public var displayName: String {
        isDefault ? L10n.string("favorites.default_category") : name
    }
}

public enum FavoriteCollectionColor: String, Codable, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray
}

public struct LocalFavoriteCollection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var categoryID: String
    public var name: String
    public var color: FavoriteCollectionColor
    public var manualOrder: Int

    public init(
        id: String = UUID().uuidString,
        categoryID: String,
        name: String,
        color: FavoriteCollectionColor = .gray,
        manualOrder: Int = 0
    ) {
        self.id = id
        self.categoryID = categoryID
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
        self.manualOrder = manualOrder
    }
}

public struct FavoriteRemoteMapping: Codable, Hashable, Sendable {
    public var yamiboFavoriteID: String?
    public var yamiboRemoteOrder: Int?
    public var lastSeenAt: Date?
    public var isMarkedRemoteMissing: Bool

    public init(
        yamiboFavoriteID: String? = nil,
        yamiboRemoteOrder: Int? = nil,
        lastSeenAt: Date? = nil,
        isMarkedRemoteMissing: Bool = false
    ) {
        self.yamiboFavoriteID = yamiboFavoriteID
        self.yamiboRemoteOrder = yamiboRemoteOrder
        self.lastSeenAt = lastSeenAt
        self.isMarkedRemoteMissing = isMarkedRemoteMissing
    }
}

public struct FavoriteMangaChapterMetadata: Codable, Hashable, Sendable {
    public var chapterTID: String
    public var chapterView: Int
    public var chapterTitle: String?
    public var importedAt: Date

    public init(chapterTID: String, chapterView: Int = 1, chapterTitle: String? = nil, importedAt: Date = .now) {
        self.chapterTID = chapterTID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterView = max(1, chapterView)
        self.chapterTitle = chapterTitle
        self.importedAt = importedAt
    }
}

public enum FavoriteContentUpdateDateResolver {
    public static func date(lastEditedText: String?, postedAtText: String?) -> Date? {
        date(from: extractedEditTime(from: lastEditedText)) ?? date(from: postedAtText)
    }

    public static func date(from text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let normalized = text.replacingOccurrences(of: "/", with: "-")
        let datePatterns = [
            #"(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?)"#,
            #"(\d{4}-\d{1,2}-\d{1,2})"#
        ]
        for pattern in datePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex ..< normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  let matchRange = Range(match.range(at: 1), in: normalized) else {
                continue
            }
            let value = String(normalized[matchRange])
            for format in formats(for: value) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
                formatter.dateFormat = format
                if let date = formatter.date(from: value) {
                    return date
                }
            }
        }
        return nil
    }

    private static func extractedEditTime(from text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let patterns = [
            #"(?:本帖最后由|本帖最後由)\s+.+?\s+(?:于|於)\s+(.+?)\s+(?:编辑|編輯)"#,
            #"(?:最后编辑于|最後編輯於)\s*(.+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return text
    }

    private static func formats(for value: String) -> [String] {
        if value.contains(":") {
            return value.split(separator: ":").count == 3
                ? ["yyyy-M-d H:mm:ss", "yyyy-MM-dd HH:mm:ss"]
                : ["yyyy-M-d H:mm", "yyyy-MM-dd HH:mm"]
        }
        return ["yyyy-M-d", "yyyy-MM-dd"]
    }
}

public struct FavoriteThreadProbeResult: Hashable, Sendable {
    public var target: FavoriteContentTarget
    public var title: String
    public var sourceGroup: FavoriteSourceGroup
    public var forumID: String?
    public var forumName: String?
    public var coverURL: URL?
    public var contentUpdatedAt: Date?
    public var authorID: String?

    public init(
        target: FavoriteContentTarget,
        title: String,
        sourceGroup: FavoriteSourceGroup = .unknown,
        forumID: String? = nil,
        forumName: String? = nil,
        coverURL: URL? = nil,
        contentUpdatedAt: Date? = nil,
        authorID: String? = nil
    ) {
        self.target = target
        self.title = title
        let forumMetadata = FavoriteSourceGroup.normalizedForumMetadata(
            sourceGroup: sourceGroup,
            forumID: forumID,
            forumName: forumName
        )
        self.sourceGroup = forumMetadata.sourceGroup
        self.forumID = forumMetadata.forumID
        self.forumName = forumMetadata.forumName
        self.coverURL = coverURL
        self.contentUpdatedAt = contentUpdatedAt
        self.authorID = authorID
    }
}

public enum FavoriteThreadImportFailure: Error, Equatable, Sendable {
    case probeFailed(String)
    case unsupportedTarget
}

public enum FavoriteItemOpenRoute: Equatable, Sendable {
    case nativeThread(URL)
    case novelDetail(threadID: String)
    case mangaTitle(cleanBookName: String)
    case unsupported
}

public struct FavoriteItem: Codable, Hashable, Identifiable, Sendable {
    public var target: FavoriteContentTarget
    public var title: String
    public var displayName: String?
    public var sourceGroup: FavoriteSourceGroup
    public var forumID: String?
    public var forumName: String?
    public var coverURL: URL?
    public var contentUpdatedAt: Date?
    public var remoteMapping: FavoriteRemoteMapping?
    public var mangaChapterMetadata: FavoriteMangaChapterMetadata?
    public var locations: [FavoriteLocation]
    public var tagIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public var id: String { target.id }

    public init(
        target: FavoriteContentTarget,
        title: String,
        displayName: String? = nil,
        sourceGroup: FavoriteSourceGroup = .unknown,
        forumID: String? = nil,
        forumName: String? = nil,
        coverURL: URL? = nil,
        contentUpdatedAt: Date? = nil,
        remoteMapping: FavoriteRemoteMapping? = nil,
        mangaChapterMetadata: FavoriteMangaChapterMetadata? = nil,
        locations: [FavoriteLocation],
        tagIDs: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) throws {
        let normalizedLocations = Self.normalizedLocations(locations)
        guard !normalizedLocations.isEmpty else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_library.item_requires_location"))
        }
        self.target = target
        self.title = title
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let forumMetadata = FavoriteSourceGroup.normalizedForumMetadata(sourceGroup: sourceGroup, forumID: forumID, forumName: forumName)
        self.sourceGroup = forumMetadata.sourceGroup
        self.forumID = forumMetadata.forumID
        self.forumName = forumMetadata.forumName
        self.coverURL = coverURL
        self.contentUpdatedAt = contentUpdatedAt
        self.remoteMapping = remoteMapping
        self.mangaChapterMetadata = mangaChapterMetadata
        self.locations = normalizedLocations
        self.tagIDs = Self.normalizedIDs(tagIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var resolvedDisplayTitle: String {
        displayName?.nilIfEmpty ?? title
    }

    static func normalizedLocations(_ locations: [FavoriteLocation]) -> [FavoriteLocation] {
        var seen: Set<String> = []
        return locations.filter { seen.insert($0.id).inserted }
    }

    static func normalizedIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

}

public struct FavoriteLibraryDocument: Codable, Equatable, Sendable {
    public var categories: [FavoriteCategory]
    public var collections: [LocalFavoriteCollection]
    public var items: [FavoriteItem]
    public var tags: [FavoriteTag]

    public init(
        categories: [FavoriteCategory] = [.defaultCategory],
        collections: [LocalFavoriteCollection] = [],
        items: [FavoriteItem] = [],
        tags: [FavoriteTag] = []
    ) {
        self.categories = Self.normalizedCategories(categories)
        self.collections = collections
        self.items = Self.normalizedItems(items, categories: self.categories, collections: collections)
        self.tags = tags
    }

    public var defaultCategory: FavoriteCategory {
        categories.first(where: \.isDefault) ?? .defaultCategory
    }

    public mutating func addItem(_ item: FavoriteItem) {
        removeItem(target: item.target)
        items.append(Self.normalizedItem(item, categories: categories, collections: collections))
        sortItems()
    }

    @discardableResult
    public mutating func importThreadFavorite(
        threadID: String,
        displayName: String? = nil,
        location: FavoriteLocation? = nil,
        remoteMapping: FavoriteRemoteMapping? = nil,
        date: Date = .now,
        probe: (String) async throws -> FavoriteThreadProbeResult
    ) async throws -> FavoriteItem {
        do {
            let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await probe(normalizedThreadID)
            return try importThreadFavorite(
                probeResult: result,
                displayName: displayName,
                location: location,
                remoteMapping: remoteMapping,
                date: date
            )
        } catch let failure as FavoriteThreadImportFailure {
            throw failure
        } catch {
            throw FavoriteThreadImportFailure.probeFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public mutating func importThreadFavorite(
        probeResult: FavoriteThreadProbeResult,
        displayName: String? = nil,
        location: FavoriteLocation? = nil,
        remoteMapping: FavoriteRemoteMapping? = nil,
        date: Date = .now
    ) throws -> FavoriteItem {
        guard probeResult.target.kind == .normalThread || probeResult.target.kind == .novelThread else {
            throw FavoriteThreadImportFailure.unsupportedTarget
        }
        let resolvedLocation = location ?? .category(defaultCategory.id)
        if let existingThreadID = probeResult.target.threadID,
           let existingTarget = items.first(where: { $0.target.threadID == existingThreadID })?.target,
           existingTarget.id != probeResult.target.id {
            retargetItem(from: existingTarget, to: probeResult.target)
        }

        if let index = items.firstIndex(where: { $0.target.id == probeResult.target.id }) {
            items[index].title = probeResult.title
            if probeResult.sourceGroup != .unknown || probeResult.forumID != nil {
                items[index].sourceGroup = probeResult.sourceGroup
                items[index].forumID = probeResult.forumID
                items[index].forumName = probeResult.forumName
            }
            items[index].coverURL = probeResult.coverURL ?? items[index].coverURL
            items[index].contentUpdatedAt = probeResult.contentUpdatedAt ?? items[index].contentUpdatedAt
            items[index].remoteMapping = remoteMapping ?? items[index].remoteMapping
            items[index].displayName = displayName?.nilIfEmpty ?? items[index].displayName
            items[index].locations = FavoriteItem.normalizedLocations(items[index].locations + [resolvedLocation])
            items[index].updatedAt = date
            items[index] = Self.normalizedItem(items[index], categories: categories, collections: collections)
            return items[index]
        }

        let item = try FavoriteItem(
            target: probeResult.target,
            title: probeResult.title,
            displayName: displayName,
            sourceGroup: probeResult.sourceGroup,
            forumID: probeResult.forumID,
            forumName: probeResult.forumName,
            coverURL: probeResult.coverURL,
            contentUpdatedAt: probeResult.contentUpdatedAt,
            remoteMapping: remoteMapping,
            locations: [resolvedLocation],
            createdAt: date,
            updatedAt: date
        )
        addItem(item)
        return item
    }

    public func openRoute(for item: FavoriteItem) -> FavoriteItemOpenRoute {
        switch item.target {
        case let .normalThread(threadID):
            .nativeThread(Self.threadURL(for: threadID))
        case let .novelThread(threadID):
            .novelDetail(threadID: threadID)
        case let .mangaTitle(_, cleanBookName):
            .mangaTitle(cleanBookName: cleanBookName)
        }
    }

    private static func threadURL(for threadID: String) -> URL {
        FavoriteLibraryURLIdentity.canonicalThreadURL(
            from: YamiboRoute.threadByID(tid: threadID, page: 1, authorID: nil, reverse: false).url
        )
    }

    @discardableResult
    public mutating func addMangaTitleFavorite(
        cleanBookName: String,
        mangaID: String? = nil,
        title: String? = nil,
        location: FavoriteLocation? = nil,
        remoteMapping: FavoriteRemoteMapping? = nil,
        contentUpdatedAt: Date? = nil,
        chapterMetadata: FavoriteMangaChapterMetadata? = nil,
        date: Date = .now
    ) throws -> FavoriteItem {
        let normalizedName = cleanBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = FavoriteContentTarget(mangaID: mangaID ?? normalizedName, mangaCleanBookName: normalizedName)
        let normalizedMangaID = target.mangaID ?? normalizedName
        let resolvedLocation = location ?? .category(defaultCategory.id)
        if let retargetIndex = mangaRetargetCandidateIndex(
            target: target,
            cleanBookName: normalizedName,
            chapterTID: chapterMetadata?.chapterTID
        ) {
            retargetItem(from: items[retargetIndex].target, to: target)
        }
        if let index = items.firstIndex(where: { $0.target.id == target.id }) {
            items[index].title = title?.nilIfEmpty ?? items[index].title
            items[index].target = target
            items[index].sourceGroup = .mangaTitle(mangaID: normalizedMangaID, cleanBookName: normalizedName)
            items[index].mangaChapterMetadata = chapterMetadata ?? items[index].mangaChapterMetadata
            items[index].remoteMapping = remoteMapping ?? items[index].remoteMapping
            items[index].contentUpdatedAt = contentUpdatedAt ?? items[index].contentUpdatedAt
            items[index].locations = FavoriteItem.normalizedLocations(items[index].locations + [resolvedLocation])
            items[index].updatedAt = date
            items[index] = Self.normalizedItem(items[index], categories: categories, collections: collections)
            return items[index]
        }

        let item = try FavoriteItem(
            target: target,
            title: title?.nilIfEmpty ?? normalizedName,
            sourceGroup: .mangaTitle(mangaID: normalizedMangaID, cleanBookName: normalizedName),
            contentUpdatedAt: contentUpdatedAt,
            remoteMapping: remoteMapping,
            mangaChapterMetadata: chapterMetadata,
            locations: [resolvedLocation],
            createdAt: date,
            updatedAt: date
        )
        addItem(item)
        return item
    }

    private func mangaRetargetCandidateIndex(
        target: FavoriteContentTarget,
        cleanBookName: String,
        chapterTID: String?
    ) -> Int? {
        guard case .mangaTitle = target else { return nil }
        var candidateIDs = Set<String>()
        candidateIDs.insert(FavoriteContentTarget(mangaCleanBookName: cleanBookName).id)
        if let chapterTID = chapterTID?.trimmingCharacters(in: .whitespacesAndNewlines), !chapterTID.isEmpty {
            candidateIDs.insert(FavoriteContentTarget(mangaID: "chapter:\(chapterTID)", mangaCleanBookName: cleanBookName).id)
            candidateIDs.insert(FavoriteContentTarget(mangaID: "thread:\(chapterTID)", mangaCleanBookName: cleanBookName).id)
        }
        candidateIDs.remove(target.id)
        return items.firstIndex { item in
            candidateIDs.contains(item.target.id) ||
                (chapterTID != nil && item.mangaChapterMetadata?.chapterTID == chapterTID && item.target.kind == .mangaTitle)
        }
    }

    @discardableResult
    public mutating func importMangaChapterFavorite(
        chapterTID: String,
        chapterView: Int = 1,
        chapterTitle: String? = nil,
        directories: [MangaDirectory],
        fallbackCleanBookName: String? = nil,
        location: FavoriteLocation? = nil,
        remoteMapping: FavoriteRemoteMapping? = nil,
        date: Date = .now
    ) throws -> FavoriteItem {
        let matchedDirectory = directories.first { directory in
            directory.chapters.contains { $0.tid == chapterTID }
        }
        let cleanBookName = matchedDirectory?.cleanBookName ?? fallbackCleanBookName?.nilIfEmpty
        let mangaID = matchedDirectory?.favoriteIdentity ?? "chapter:\(chapterTID)"

        guard let cleanBookName else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_library.manga_title_resolution_failed"))
        }

        return try addMangaTitleFavorite(
            cleanBookName: cleanBookName,
            mangaID: mangaID,
            title: cleanBookName,
            location: location,
            remoteMapping: remoteMapping,
            contentUpdatedAt: matchedDirectory?.lastUpdatedAt,
            chapterMetadata: FavoriteMangaChapterMetadata(
                chapterTID: chapterTID,
                chapterView: chapterView,
                chapterTitle: chapterTitle,
                importedAt: date
            ),
            date: date
        )
    }

    public mutating func renameMangaTitle(from oldCleanBookName: String, to newCleanBookName: String) {
        let oldTarget = items.first { item in
            item.target.mangaCleanBookName == oldCleanBookName
        }?.target ?? FavoriteContentTarget(mangaCleanBookName: oldCleanBookName)
        let newTarget = oldTarget.renamedMangaTitle(to: newCleanBookName)
        retargetItem(from: oldTarget, to: newTarget)
        if let index = items.firstIndex(where: { $0.target.id == newTarget.id }) {
            items[index].sourceGroup = .mangaTitle(mangaID: newTarget.mangaID ?? newCleanBookName, cleanBookName: newCleanBookName)
            if items[index].title == oldCleanBookName {
                items[index].title = newCleanBookName
            }
        }
    }

    public mutating func removeItem(target: FavoriteContentTarget) {
        items.removeAll { $0.target.id == target.id }
    }

    public mutating func markRemoteMappingMissing(for target: FavoriteContentTarget, date: Date = .now) {
        guard let index = items.firstIndex(where: { $0.target.id == target.id }) else { return }
        var mapping = items[index].remoteMapping ?? FavoriteRemoteMapping()
        mapping.isMarkedRemoteMissing = true
        mapping.lastSeenAt = date
        items[index].remoteMapping = mapping
        items[index].updatedAt = date
    }

    public mutating func retargetItem(from oldTarget: FavoriteContentTarget, to newTarget: FavoriteContentTarget) {
        guard let index = items.firstIndex(where: { $0.target.id == oldTarget.id }) else { return }
        var replacement = items[index]
        replacement.target = newTarget
        if oldTarget.id == newTarget.id {
            items[index] = replacement
            sortItems()
            return
        }
        if let duplicateIndex = items.firstIndex(where: { $0.target.id == newTarget.id }) {
            replacement.locations = FavoriteItem.normalizedLocations(items[duplicateIndex].locations + replacement.locations)
            replacement.tagIDs = FavoriteItem.normalizedIDs(items[duplicateIndex].tagIDs + replacement.tagIDs)
            items.remove(at: duplicateIndex)
        }
        if let updatedIndex = items.firstIndex(where: { $0.target.id == oldTarget.id }) {
            items[updatedIndex] = replacement
        } else {
            items.append(replacement)
        }
        sortItems()
    }

    public mutating func addLocation(_ location: FavoriteLocation, to target: FavoriteContentTarget) {
        guard let index = items.firstIndex(where: { $0.target.id == target.id }) else { return }
        items[index].locations = FavoriteItem.normalizedLocations(items[index].locations + [location])
        items[index] = Self.normalizedItem(items[index], categories: categories, collections: collections)
    }

    @discardableResult
    public mutating func removeLocation(_ location: FavoriteLocation, from target: FavoriteContentTarget) -> Bool {
        guard let index = items.firstIndex(where: { $0.target.id == target.id }) else { return false }
        let remaining = items[index].locations.filter { $0 != location }
        guard !remaining.isEmpty else { return false }
        items[index].locations = remaining
        return true
    }

    public mutating func createCategory(name: String) -> FavoriteCategory {
        let category = FavoriteCategory(
            name: name,
            manualOrder: ((categories.map(\.manualOrder).max() ?? -1) + 1),
            isDefault: false
        )
        categories.append(category)
        categories = Self.normalizedCategories(categories)
        return category
    }

    public mutating func renameCategory(id: String, name: String) {
        guard let index = categories.firstIndex(where: { $0.id == id && !$0.isDefault }) else { return }
        categories[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func reorderCategories(orderedIDs: [String]) {
        let orderByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset + 1) })
        categories = categories.map { category in
            var category = category
            guard !category.isDefault, let order = orderByID[category.id] else { return category }
            category.manualOrder = order
            return category
        }
        categories = Self.normalizedCategories(categories)
    }

    public mutating func deleteCategory(id: String) {
        guard categories.contains(where: { $0.id == id && !$0.isDefault }) else { return }
        let defaultLocation = FavoriteLocation.category(defaultCategory.id)
        categories.removeAll { $0.id == id && !$0.isDefault }
        collections.removeAll { $0.categoryID == id }
        items = items.map { item in
            var item = item
            let remaining = item.locations.filter { $0.categoryID != id }
            item.locations = FavoriteItem.normalizedLocations(remaining.isEmpty ? [defaultLocation] : remaining)
            return item
        }
    }

    public mutating func createCollection(
        categoryID: String,
        name: String,
        color: FavoriteCollectionColor = .gray
    ) -> LocalFavoriteCollection {
        let collection = LocalFavoriteCollection(
            categoryID: categoryID,
            name: name,
            color: color,
            manualOrder: ((collections.filter { $0.categoryID == categoryID }.map(\.manualOrder).max() ?? -1) + 1)
        )
        collections.append(collection)
        return collection
    }

    public mutating func renameCollection(id collectionID: String, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func recolorCollection(id collectionID: String, color: FavoriteCollectionColor) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].color = color
    }

    public mutating func moveCollection(id collectionID: String, toCategoryID categoryID: String) {
        guard categories.contains(where: { $0.id == categoryID }),
              let index = collections.firstIndex(where: { $0.id == collectionID }) else {
            return
        }
        let previousCategoryID = collections[index].categoryID
        guard previousCategoryID != categoryID else { return }
        collections[index].categoryID = categoryID
        collections[index].manualOrder = ((collections.filter { $0.categoryID == categoryID }.map(\.manualOrder).max() ?? -1) + 1)
        items = items.map { item in
            var item = item
            item.locations = item.locations.map { location in
                location == .collection(categoryID: previousCategoryID, collectionID: collectionID)
                    ? .collection(categoryID: categoryID, collectionID: collectionID)
                    : location
            }
            item.locations = FavoriteItem.normalizedLocations(item.locations)
            return item
        }
    }

    public mutating func reorderCollections(categoryID: String, orderedIDs: [String]) {
        let orderByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        collections = collections.map { collection in
            var collection = collection
            guard collection.categoryID == categoryID, let order = orderByID[collection.id] else { return collection }
            collection.manualOrder = order
            return collection
        }
    }

    public mutating func dissolveCollection(id collectionID: String) {
        guard let collection = collections.first(where: { $0.id == collectionID }) else { return }
        let parentLocation = FavoriteLocation.category(collection.categoryID)
        collections.removeAll { $0.id == collectionID }
        items = items.map { item in
            var item = item
            if item.locations.contains(.collection(categoryID: collection.categoryID, collectionID: collectionID)) {
                item.locations.removeAll { $0 == .collection(categoryID: collection.categoryID, collectionID: collectionID) }
                item.locations = FavoriteItem.normalizedLocations(item.locations + [parentLocation])
            }
            return item
        }
    }

    public mutating func createTag(name: String, color: FavoriteTagColor, date: Date = .now) -> FavoriteTag {
        let tag = FavoriteTag(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            manualOrder: ((tags.map(\.manualOrder).max() ?? -1) + 1),
            createdAt: date,
            updatedAt: date
        )
        tags.append(tag)
        return tag
    }

    public mutating func renameTag(id tagID: String, name: String, date: Date = .now) {
        guard let index = tags.firstIndex(where: { $0.id == tagID }) else { return }
        tags[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[index].updatedAt = date
    }

    public mutating func recolorTag(id tagID: String, color: FavoriteTagColor, date: Date = .now) {
        guard let index = tags.firstIndex(where: { $0.id == tagID }) else { return }
        tags[index].color = color
        tags[index].updatedAt = date
    }

    public mutating func deleteTag(id tagID: String) {
        tags.removeAll { $0.id == tagID }
        items = items.map { item in
            var item = item
            item.tagIDs.removeAll { $0 == tagID }
            return item
        }
    }

    public mutating func assignTag(id tagID: String, to target: FavoriteContentTarget) {
        guard tags.contains(where: { $0.id == tagID }),
              let index = items.firstIndex(where: { $0.target.id == target.id }) else { return }
        items[index].tagIDs = FavoriteItem.normalizedIDs(items[index].tagIDs + [tagID])
    }

    public mutating func unassignTag(id tagID: String, from target: FavoriteContentTarget) {
        guard let index = items.firstIndex(where: { $0.target.id == target.id }) else { return }
        items[index].tagIDs.removeAll { $0 == tagID }
    }

    private mutating func sortItems() {
        items.sort { lhs, rhs in lhs.id < rhs.id }
    }

    private static func normalizedCategories(_ categories: [FavoriteCategory]) -> [FavoriteCategory] {
        var result = categories
        if !result.contains(where: \.isDefault) {
            result.insert(.defaultCategory, at: 0)
        }
        if result.filter(\.isDefault).count > 1 {
            var foundDefault = false
            result = result.map { category in
                var category = category
                if category.isDefault {
                    category.isDefault = !foundDefault
                    foundDefault = true
                }
                return category
            }
        }
        result = result.map { category in
            var category = category
            if category.isDefault {
                category.name = FavoriteCategory.defaultStorageName
            }
            return category
        }
        return result.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private static func normalizedItems(
        _ items: [FavoriteItem],
        categories: [FavoriteCategory],
        collections: [LocalFavoriteCollection]
    ) -> [FavoriteItem] {
        items.map { normalizedItem($0, categories: categories, collections: collections) }
            .sorted { lhs, rhs in lhs.id < rhs.id }
    }

    private static func normalizedItem(
        _ item: FavoriteItem,
        categories: [FavoriteCategory],
        collections: [LocalFavoriteCollection]
    ) -> FavoriteItem {
        var item = item
        let forumMetadata = FavoriteSourceGroup.normalizedForumMetadata(
            sourceGroup: item.sourceGroup,
            forumID: item.forumID,
            forumName: item.forumName
        )
        item.sourceGroup = forumMetadata.sourceGroup
        item.forumID = forumMetadata.forumID
        item.forumName = forumMetadata.forumName
        let validCategoryIDs = Set(categories.map(\.id))
        let validCollectionIDsByCategory = Dictionary(grouping: collections, by: \.categoryID)
            .mapValues { Set($0.map(\.id)) }
        let filtered = item.locations.filter { location in
            guard validCategoryIDs.contains(location.categoryID) else { return false }
            guard let collectionID = location.collectionID else { return true }
            return validCollectionIDsByCategory[location.categoryID, default: []].contains(collectionID)
        }
        item.locations = filtered.isEmpty ? [.category(categories.first(where: \.isDefault)?.id ?? FavoriteCategory.defaultID)] : filtered
        item.tagIDs = FavoriteItem.normalizedIDs(item.tagIDs)
        return item
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
