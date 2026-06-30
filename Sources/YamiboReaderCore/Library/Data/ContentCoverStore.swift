import Foundation

public enum ContentCoverTargetType: String, Codable, Hashable, Sendable {
    case threadNormal = "ThreadNormal"
    case threadNovel = "ThreadNovel"
    case tagManga = "TagManga"
}

public struct ContentCoverKey: Codable, Hashable, Sendable {
    public var targetType: ContentCoverTargetType
    public var targetID: String

    public init(targetType: ContentCoverTargetType, targetID: String) {
        self.targetType = targetType
        self.targetID = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ContentCover: Codable, Hashable, Sendable {
    public var key: ContentCoverKey
    public var automaticCoverURL: URL?
    public var manualCoverURL: URL?
    public var dynamicEnabled: Bool
    public var updatedAt: Date

    public init(
        key: ContentCoverKey,
        automaticCoverURL: URL? = nil,
        manualCoverURL: URL? = nil,
        dynamicEnabled: Bool = true,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.automaticCoverURL = automaticCoverURL
        self.manualCoverURL = manualCoverURL
        self.dynamicEnabled = dynamicEnabled
        self.updatedAt = updatedAt
    }

    public var resolvedURL: URL? {
        if dynamicEnabled {
            automaticCoverURL ?? manualCoverURL
        } else {
            manualCoverURL ?? automaticCoverURL
        }
    }
}

public protocol ContentCoverStoring: Sendable {
    func cover(for key: ContentCoverKey) async -> ContentCover?
    @discardableResult
    func setAutomaticCover(_ url: URL, for key: ContentCoverKey, date: Date) async throws -> Bool
    @discardableResult
    func setManualCover(_ url: URL, for key: ContentCoverKey, date: Date) async throws -> Bool
    func setDynamicEnabled(_ enabled: Bool, for key: ContentCoverKey, date: Date) async throws
    func clearAll() async throws
}

public actor ContentCoverStore: ContentCoverStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "yamibo.contentCovers") {
        self.defaults = defaults
        self.key = key
    }

    public func cover(for key: ContentCoverKey) async -> ContentCover? {
        guard !key.targetID.isEmpty else { return nil }
        return loadCovers()[key]
    }

    @discardableResult
    public func setAutomaticCover(_ url: URL, for key: ContentCoverKey, date: Date = .now) async throws -> Bool {
        guard let normalizedURL = Self.normalizedCoverURL(from: url.absoluteString),
              !key.targetID.isEmpty else {
            return false
        }
        var covers = loadCovers()
        var cover = covers[key] ?? ContentCover(key: key)
        cover.automaticCoverURL = normalizedURL
        cover.updatedAt = date
        covers[key] = cover
        try persist(covers)
        return true
    }

    @discardableResult
    public func setManualCover(_ url: URL, for key: ContentCoverKey, date: Date = .now) async throws -> Bool {
        guard let normalizedURL = Self.normalizedCoverURL(from: url.absoluteString),
              !key.targetID.isEmpty else {
            return false
        }
        var covers = loadCovers()
        var cover = covers[key] ?? ContentCover(key: key)
        cover.manualCoverURL = normalizedURL
        cover.dynamicEnabled = false
        cover.updatedAt = date
        covers[key] = cover
        try persist(covers)
        return true
    }

    public func setDynamicEnabled(_ enabled: Bool, for key: ContentCoverKey, date: Date = .now) async throws {
        guard !key.targetID.isEmpty else { return }
        var covers = loadCovers()
        var cover = covers[key] ?? ContentCover(key: key)
        cover.dynamicEnabled = enabled
        cover.updatedAt = date
        covers[key] = cover
        try persist(covers)
    }

    public func clearAll() async throws {
        defaults.removeObject(forKey: key)
    }

    public static func normalizedCoverURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("data:"),
              !lowercased.hasPrefix("blob:"),
              !lowercased.contains("none.gif"),
              !lowercased.contains("static/image/"),
              !lowercased.contains("/smiley/"),
              !lowercased.contains("/face/") else {
            return nil
        }

        if lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://") {
            return URL(string: value)
        }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        if value.hasPrefix("/") {
            return URL(string: "https://bbs.yamibo.com\(value)")
        }
        return URL(string: "https://bbs.yamibo.com/\(value)")
    }

    private func loadCovers() -> [ContentCoverKey: ContentCover] {
        guard let data = defaults.data(forKey: key),
              let covers = try? decoder.decode([ContentCover].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: covers.map { ($0.key, $0) })
    }

    private func persist(_ covers: [ContentCoverKey: ContentCover]) throws {
        let sorted = covers.values.sorted { lhs, rhs in
            if lhs.key.targetType.rawValue == rhs.key.targetType.rawValue {
                return lhs.key.targetID < rhs.key.targetID
            }
            return lhs.key.targetType.rawValue < rhs.key.targetType.rawValue
        }
        defaults.set(try encoder.encode(sorted), forKey: key)
    }
}
