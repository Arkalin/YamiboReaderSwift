import Foundation

public enum ReaderCacheVariant: Hashable, Codable, Sendable {
    case author(String)
    case source(ReaderContentSource)

    public var key: String {
        switch self {
        case let .author(authorID):
            return "author:\(authorID)"
        case let .source(contentSource):
            return "source:\(contentSource.rawValue)"
        }
    }
}

public struct ReaderCacheIdentity: Hashable, Codable, Sendable {
    public let threadID: String
    public let threadKey: String
    public let variant: ReaderCacheVariant
    public let view: Int

    public var variantKey: String {
        variant.key
    }

    public var cacheKey: String {
        "\(threadKey)#\(variantKey)#\(view)"
    }

    public init(threadID: String, view: Int, authorID: String?, contentSource: ReaderContentSource?) {
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedThreadID.isEmpty, "ReaderCacheIdentity requires a Yamibo thread tid")
        self.threadID = normalizedThreadID
        self.threadKey = "tid:\(normalizedThreadID)"
        self.variant = Self.resolveVariant(authorID: authorID, contentSource: contentSource)
        self.view = max(1, view)
    }

    public init(request: ReaderPageRequest, contentSource: ReaderContentSource? = nil) {
        self.init(
            threadID: request.threadID,
            view: request.view,
            authorID: request.authorID,
            contentSource: contentSource
        )
    }

    public init(projection: NovelReaderProjection) {
        self.init(
            threadID: projection.threadID,
            view: projection.view,
            authorID: projection.resolvedAuthorID,
            contentSource: projection.contentSource
        )
    }

    private static func resolveVariant(authorID: String?, contentSource: ReaderContentSource?) -> ReaderCacheVariant {
        if let normalizedAuthorID = normalizedAuthorID(authorID) {
            return .author(normalizedAuthorID)
        }
        return .source(contentSource ?? .fallbackUnfilteredPage)
    }

    private static func normalizedAuthorID(_ authorID: String?) -> String? {
        let trimmed = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

}
