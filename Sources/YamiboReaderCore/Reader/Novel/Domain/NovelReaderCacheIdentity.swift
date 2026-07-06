import Foundation

enum NovelReaderCacheVariant: Hashable, Codable, Sendable {
    case author(String)
    case source(ReaderProjectionContentSource)

    var key: String {
        switch self {
        case let .author(authorID):
            return "author:\(authorID)"
        case let .source(contentSource):
            return "source:\(contentSource.rawValue)"
        }
    }
}

struct NovelReaderCacheIdentity: Hashable, Codable, Sendable {
    let threadID: String
    let threadKey: String
    let variant: NovelReaderCacheVariant
    let view: Int

    var variantKey: String {
        variant.key
    }

    var cacheKey: String {
        "\(threadKey)#\(variantKey)#\(view)"
    }

    init(threadID: String, view: Int, authorID: String?, contentSource: ReaderProjectionContentSource?) {
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedThreadID.isEmpty, "NovelReaderCacheIdentity requires a Yamibo thread tid")
        self.threadID = normalizedThreadID
        self.threadKey = "tid:\(normalizedThreadID)"
        self.variant = Self.resolveVariant(authorID: authorID, contentSource: contentSource)
        self.view = max(1, view)
    }

    init(request: NovelPageRequest, contentSource: ReaderProjectionContentSource? = nil) {
        self.init(
            threadID: request.threadID,
            view: request.view,
            authorID: request.authorID,
            contentSource: contentSource
        )
    }

    init(projection: NovelReaderProjection) {
        self.init(
            threadID: projection.threadID,
            view: projection.view,
            authorID: projection.resolvedAuthorID,
            contentSource: projection.contentSource
        )
    }

    private static func resolveVariant(authorID: String?, contentSource: ReaderProjectionContentSource?) -> NovelReaderCacheVariant {
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
