import Foundation

public enum FavoriteContentTargetKind: String, Codable, CaseIterable, Sendable {
    case normalThread
    case novelThread
    case mangaTitle
}

public enum FavoriteContentTarget: Codable, Hashable, Identifiable, Sendable {
    case normalThread(threadID: String, canonicalURL: URL)
    case novelThread(threadID: String, canonicalURL: URL)
    case mangaTitle(cleanBookName: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case threadID
        case canonicalURL
        case cleanBookName
    }

    public var id: String {
        switch self {
        case let .normalThread(threadID, _):
            "thread:normal:\(threadID)"
        case let .novelThread(threadID, _):
            "thread:novel:\(threadID)"
        case let .mangaTitle(cleanBookName):
            "manga-title:\(cleanBookName)"
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

    public var canonicalURL: URL? {
        switch self {
        case let .normalThread(_, canonicalURL), let .novelThread(_, canonicalURL):
            canonicalURL
        case .mangaTitle:
            nil
        }
    }

    public var threadID: String? {
        switch self {
        case let .normalThread(threadID, _), let .novelThread(threadID, _):
            threadID
        case .mangaTitle:
            nil
        }
    }

    public init(kind: FavoriteContentTargetKind, threadURL: URL) {
        let canonicalURL = FavoriteLibraryURLIdentity.canonicalThreadURL(from: threadURL)
        let threadID = YamiboThreadURLCanonicalizer.threadID(from: canonicalURL) ?? canonicalURL.absoluteString
        switch kind {
        case .normalThread:
            self = .normalThread(threadID: threadID, canonicalURL: canonicalURL)
        case .novelThread:
            self = .novelThread(threadID: threadID, canonicalURL: canonicalURL)
        case .mangaTitle:
            self = .mangaTitle(cleanBookName: threadID)
        }
    }

    public init(mangaCleanBookName: String) {
        self = .mangaTitle(cleanBookName: mangaCleanBookName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(FavoriteContentTargetKind.self, forKey: .kind)
        switch kind {
        case .normalThread:
            self = .normalThread(
                threadID: try container.decode(String.self, forKey: .threadID),
                canonicalURL: try container.decode(URL.self, forKey: .canonicalURL)
            )
        case .novelThread:
            self = .novelThread(
                threadID: try container.decode(String.self, forKey: .threadID),
                canonicalURL: try container.decode(URL.self, forKey: .canonicalURL)
            )
        case .mangaTitle:
            self = .mangaTitle(cleanBookName: try container.decode(String.self, forKey: .cleanBookName))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .normalThread(threadID, canonicalURL), let .novelThread(threadID, canonicalURL):
            try container.encode(threadID, forKey: .threadID)
            try container.encode(canonicalURL, forKey: .canonicalURL)
        case let .mangaTitle(cleanBookName):
            try container.encode(cleanBookName, forKey: .cleanBookName)
        }
    }
}

public enum FavoriteSourceGroup: Codable, Hashable, Sendable {
    case forumBoard(id: String, label: String)
    case mangaTitle(cleanBookName: String)
    case unknown
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
        FavoriteCategory(id: defaultID, name: L10n.string("favorites.default_category"), manualOrder: 0, isDefault: true)
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
    public var chapterURL: URL
    public var chapterTitle: String?
    public var importedAt: Date

    public init(chapterTID: String, chapterURL: URL, chapterTitle: String? = nil, importedAt: Date = .now) {
        self.chapterTID = chapterTID
        self.chapterURL = chapterURL
        self.chapterTitle = chapterTitle
        self.importedAt = importedAt
    }
}

public struct FavoriteThreadProbeResult: Hashable, Sendable {
    public var target: FavoriteContentTarget
    public var title: String
    public var sourceGroup: FavoriteSourceGroup
    public var coverURL: URL?
    public var authorID: String?

    public init(
        target: FavoriteContentTarget,
        title: String,
        sourceGroup: FavoriteSourceGroup = .unknown,
        coverURL: URL? = nil,
        authorID: String? = nil
    ) {
        self.target = target
        self.title = title
        self.sourceGroup = sourceGroup
        self.coverURL = coverURL
        self.authorID = authorID
    }
}

public enum FavoriteThreadImportFailure: Error, Equatable, Sendable {
    case probeFailed(String)
    case unsupportedTarget
}

public enum FavoriteItemOpenRoute: Equatable, Sendable {
    case nativeThread(URL)
    case novelDetail(URL)
    case mangaTitle(cleanBookName: String)
    case unsupported
}

public struct FavoriteItem: Codable, Hashable, Identifiable, Sendable {
    public var target: FavoriteContentTarget
    public var title: String
    public var displayName: String?
    public var sourceGroup: FavoriteSourceGroup
    public var coverURL: URL?
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
        coverURL: URL? = nil,
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
        self.sourceGroup = sourceGroup
        self.coverURL = coverURL
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
        threadURL: URL,
        displayName: String? = nil,
        location: FavoriteLocation? = nil,
        remoteMapping: FavoriteRemoteMapping? = nil,
        date: Date = .now,
        probe: (URL) async throws -> FavoriteThreadProbeResult
    ) async throws -> FavoriteItem {
        do {
            let result = try await probe(threadURL)
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
            items[index].sourceGroup = probeResult.sourceGroup
            items[index].coverURL = probeResult.coverURL ?? items[index].coverURL
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
            coverURL: probeResult.coverURL,
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
        case let .normalThread(_, canonicalURL):
            .nativeThread(canonicalURL)
        case let .novelThread(_, canonicalURL):
            .novelDetail(canonicalURL)
        case let .mangaTitle(cleanBookName):
            .mangaTitle(cleanBookName: cleanBookName)
        }
    }

    @discardableResult
    public mutating func addMangaTitleFavorite(
        cleanBookName: String,
        title: String? = nil,
        location: FavoriteLocation? = nil,
        chapterMetadata: FavoriteMangaChapterMetadata? = nil,
        date: Date = .now
    ) throws -> FavoriteItem {
        let normalizedName = cleanBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = FavoriteContentTarget(mangaCleanBookName: normalizedName)
        let resolvedLocation = location ?? .category(defaultCategory.id)
        if let index = items.firstIndex(where: { $0.target.id == target.id }) {
            items[index].title = title?.nilIfEmpty ?? items[index].title
            items[index].sourceGroup = .mangaTitle(cleanBookName: normalizedName)
            items[index].mangaChapterMetadata = chapterMetadata ?? items[index].mangaChapterMetadata
            items[index].locations = FavoriteItem.normalizedLocations(items[index].locations + [resolvedLocation])
            items[index].updatedAt = date
            items[index] = Self.normalizedItem(items[index], categories: categories, collections: collections)
            return items[index]
        }

        let item = try FavoriteItem(
            target: target,
            title: title?.nilIfEmpty ?? normalizedName,
            sourceGroup: .mangaTitle(cleanBookName: normalizedName),
            mangaChapterMetadata: chapterMetadata,
            locations: [resolvedLocation],
            createdAt: date,
            updatedAt: date
        )
        addItem(item)
        return item
    }

    @discardableResult
    public mutating func importMangaChapterFavorite(
        chapterTID: String,
        chapterURL: URL,
        chapterTitle: String? = nil,
        directories: [MangaDirectory],
        fallbackCleanBookName: String? = nil,
        date: Date = .now
    ) throws -> FavoriteItem {
        let cleanBookName = directories.first { directory in
            directory.chapters.contains { $0.tid == chapterTID }
        }?.cleanBookName ?? fallbackCleanBookName?.nilIfEmpty

        guard let cleanBookName else {
            throw YamiboError.persistenceFailed(L10n.string("favorite_library.manga_title_resolution_failed"))
        }

        return try addMangaTitleFavorite(
            cleanBookName: cleanBookName,
            title: cleanBookName,
            chapterMetadata: FavoriteMangaChapterMetadata(
                chapterTID: chapterTID,
                chapterURL: chapterURL,
                chapterTitle: chapterTitle,
                importedAt: date
            ),
            date: date
        )
    }

    public mutating func renameMangaTitle(from oldCleanBookName: String, to newCleanBookName: String) {
        let oldTarget = FavoriteContentTarget(mangaCleanBookName: oldCleanBookName)
        let newTarget = FavoriteContentTarget(mangaCleanBookName: newCleanBookName)
        retargetItem(from: oldTarget, to: newTarget)
        if let index = items.firstIndex(where: { $0.target.id == newTarget.id }) {
            items[index].sourceGroup = .mangaTitle(cleanBookName: newCleanBookName)
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

    public static func rebuildFromLegacy(snapshot: FavoriteLibrarySnapshot, date: Date = .now) -> FavoriteLibraryDocument {
        var document = FavoriteLibraryDocument()
        for favorite in snapshot.favorites {
            let kind: FavoriteContentTargetKind = favorite.type == .novel ? .novelThread : .normalThread
            let target = FavoriteContentTarget(kind: kind, threadURL: favorite.url)
            guard let item = try? FavoriteItem(
                target: target,
                title: favorite.title,
                displayName: favorite.displayName,
                remoteMapping: favorite.remoteFavoriteID.map { FavoriteRemoteMapping(yamiboFavoriteID: $0, lastSeenAt: date) },
                locations: [.category(document.defaultCategory.id)],
                tagIDs: favorite.tagIDs,
                createdAt: date,
                updatedAt: date
            ) else {
                continue
            }
            document.addItem(item)
        }
        document.tags = snapshot.tags
        return document
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

public actor LocalFirstFavoriteLibraryStore {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.favoriteLibrary.localFirst") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> FavoriteLibraryDocument {
        guard let data = defaults.data(forKey: key),
              let document = try? decoder.decode(FavoriteLibraryDocument.self, from: data) else {
            return FavoriteLibraryDocument()
        }
        return FavoriteLibraryDocument(
            categories: document.categories,
            collections: document.collections,
            items: document.items,
            tags: document.tags
        )
    }

    public func save(_ document: FavoriteLibraryDocument) async throws {
        do {
            try defaults.set(encoder.encode(document), forKey: key)
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func rebuildFromLegacy(_ snapshot: FavoriteLibrarySnapshot, date: Date = .now) async throws -> FavoriteLibraryDocument {
        let document = FavoriteLibraryDocument.rebuildFromLegacy(snapshot: snapshot, date: date)
        try await save(document)
        return document
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
