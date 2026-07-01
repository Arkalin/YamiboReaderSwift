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
    public let threadURL: URL
    public let threadKey: String
    public let variant: ReaderCacheVariant
    public let view: Int

    public var variantKey: String {
        variant.key
    }

    public var cacheKey: String {
        "\(threadKey)#\(variantKey)#\(view)"
    }

    public init(threadURL: URL, view: Int, authorID: String?, contentSource: ReaderContentSource?) {
        let canonicalThreadURL = Self.canonicalThreadURL(from: threadURL)
        self.threadURL = canonicalThreadURL
        self.threadKey = canonicalThreadURL.absoluteString
        self.variant = Self.resolveVariant(authorID: authorID, contentSource: contentSource)
        self.view = max(1, view)
    }

    public init(request: ReaderPageRequest, contentSource: ReaderContentSource? = nil) {
        self.init(
            threadURL: request.threadURL,
            view: request.view,
            authorID: request.authorID,
            contentSource: contentSource
        )
    }

    public init(document: ReaderPageDocument) {
        self.init(
            threadURL: document.threadURL,
            view: document.view,
            authorID: document.resolvedAuthorID,
            contentSource: document.contentSource
        )
    }

    public static func canonicalThreadURL(from url: URL) -> URL {
        YamiboThreadURLCanonicalizer.canonicalThreadURL(from: url)
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
