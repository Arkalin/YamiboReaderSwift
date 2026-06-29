import Foundation

public actor ForumCacheStore {
    private static let schemaVersion = 1
    public static let homeTTL: TimeInterval = 12 * 60 * 60
    public static let boardTTL: TimeInterval = 2 * 60 * 60

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let now: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("forum-cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("forum-cache", isDirectory: true)
        self.now = now
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadHome(allowExpired: Bool = false) async -> ForumHomePage? {
        guard let entry: ForumCacheEntry<ForumHomePage> = load(fileName: "home.json") else { return nil }
        guard allowExpired || !isExpired(entry.fetchedAt, ttl: Self.homeTTL) else { return nil }
        return entry.value
    }

    public func saveHome(_ page: ForumHomePage) async throws {
        try save(ForumCacheEntry(value: page, fetchedAt: page.fetchedAt), fileName: "home.json")
    }

    public func loadBoard(
        fid: String,
        page: Int = 1,
        filterID: String? = nil,
        orderFilter: String? = nil,
        orderBy: String? = nil,
        allowExpired: Bool = false
    ) async -> ForumBoardPage? {
        guard let entry: ForumCacheEntry<ForumBoardPage> = load(fileName: boardFileName(fid: fid, page: page, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy)) else {
            return nil
        }
        guard allowExpired || !isExpired(entry.fetchedAt, ttl: Self.boardTTL) else { return nil }
        return entry.value
    }

    public func saveBoard(
        _ page: ForumBoardPage,
        fid: String,
        pageNumber: Int = 1,
        filterID: String? = nil,
        orderFilter: String? = nil,
        orderBy: String? = nil
    ) async throws {
        try save(
            ForumCacheEntry(value: page, fetchedAt: page.fetchedAt),
            fileName: boardFileName(fid: fid, page: pageNumber, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy)
        )
    }

    public func clearAll() async throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.removeItem(at: baseDirectory)
    }

    private func load<Value: Codable>(fileName: String) -> ForumCacheEntry<Value>? {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(ForumCacheEnvelope<Value>.self, from: data),
              envelope.version == Self.schemaVersion else {
            return nil
        }
        return envelope.entry
    }

    private func save<Value: Codable>(_ entry: ForumCacheEntry<Value>, fileName: String) throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(ForumCacheEnvelope(version: Self.schemaVersion, entry: entry))
        try data.write(to: baseDirectory.appendingPathComponent(fileName, isDirectory: false), options: [.atomic])
    }

    private func isExpired(_ fetchedAt: Date, ttl: TimeInterval) -> Bool {
        now().timeIntervalSince(fetchedAt) > ttl
    }

    private func boardFileName(fid: String, page: Int, filterID: String?, orderFilter: String?, orderBy: String?) -> String {
        let key = [
            fid,
            String(max(1, page)),
            filterID?.nilIfBlank ?? "all",
            orderFilter?.nilIfBlank ?? "default",
            orderBy?.nilIfBlank ?? "default"
        ].joined(separator: "_")
        return "board_\(stableIdentifier(for: key)).json"
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}

private struct ForumCacheEnvelope<Value: Codable>: Codable {
    var version: Int
    var entry: ForumCacheEntry<Value>
}

private struct ForumCacheEntry<Value: Codable>: Codable {
    var value: Value
    var fetchedAt: Date
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
