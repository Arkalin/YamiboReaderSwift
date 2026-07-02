import CryptoKit
import Foundation

public struct YamiboImageCacheNamespace: Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func namespace(cookie: String, userAgent: String) -> YamiboImageCacheNamespace {
        ordinarySessionNamespace(cookie: cookie, userAgent: userAgent)
    }

    public static func ordinarySessionNamespace(cookie: String, userAgent: String) -> YamiboImageCacheNamespace {
        let rawValue = "\(userAgent)\u{1F}\(cookie)"
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return YamiboImageCacheNamespace(
            value: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    public static func avatarSessionNamespace(cookie: String, userAgent: String) -> YamiboImageCacheNamespace {
        let ordinary = ordinarySessionNamespace(cookie: cookie, userAgent: userAgent)
        return YamiboImageCacheNamespace(value: "avatar:\(ordinary.value)")
    }
}

public struct YamiboImageRequest: Hashable, Sendable {
    public var url: URL
    public var refererURL: URL?
    public var cacheNamespace: YamiboImageCacheNamespace

    public init(
        url: URL,
        refererURL: URL? = nil,
        cacheNamespace: YamiboImageCacheNamespace
    ) {
        self.url = url
        self.refererURL = refererURL
        self.cacheNamespace = cacheNamespace
    }

    public var cacheKey: String {
        [
            url.absoluteString,
            refererURL?.absoluteString ?? "",
            cacheNamespace.value
        ].joined(separator: "\u{1F}")
    }

    public var persistentCacheKey: String {
        [
            cacheNamespace.value,
            url.absoluteString
        ].joined(separator: "\u{1F}")
    }
}

public protocol YamiboImageDataLoading: Sendable {
    func imageData(for request: YamiboImageRequest) async throws -> Data
}

public enum YamiboImageDataCacheRetentionPolicy: String, CaseIterable, Sendable {
    case evictable
    case protected
}

public protocol YamiboImageDataCaching: Sendable {
    func data(for request: YamiboImageRequest) async -> Data?
    func save(
        _ data: Data,
        for request: YamiboImageRequest,
        retentionPolicy: YamiboImageDataCacheRetentionPolicy
    ) async throws
    func clearAll() async throws
}

public struct YamiboImageLoadingContext: Sendable {
    public let dataLoader: any YamiboImageDataLoading
    public let cacheNamespace: YamiboImageCacheNamespace

    public init(
        dataLoader: any YamiboImageDataLoading,
        cacheNamespace: YamiboImageCacheNamespace
    ) {
        self.dataLoader = dataLoader
        self.cacheNamespace = cacheNamespace
    }
}

public actor YamiboImageDataLoader: YamiboImageDataLoading {
    private let client: YamiboClient
    private let pipeline: YamiboNukeImageDataPipeline

    public init(
        client: YamiboClient,
        pipeline: YamiboNukeImageDataPipeline = .shared
    ) {
        self.client = client
        self.pipeline = pipeline
    }

    public func imageData(for request: YamiboImageRequest) async throws -> Data {
        try await pipeline.imageData(for: request, client: client)
    }
}
