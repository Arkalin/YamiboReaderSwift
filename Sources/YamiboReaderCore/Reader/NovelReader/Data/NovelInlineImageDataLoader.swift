import Foundation

public protocol NovelInlineImageDataLoading: Sendable {
    func imageData(for imageURL: URL, refererURL: URL) async throws -> Data
}

public struct NovelInlineImageCacheNamespace: Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func namespace(cookie: String, userAgent: String) -> NovelInlineImageCacheNamespace {
        NovelInlineImageCacheNamespace(
            value: YamiboImageCacheNamespace.namespace(cookie: cookie, userAgent: userAgent).value
        )
    }

    public var yamiboImageCacheNamespace: YamiboImageCacheNamespace {
        YamiboImageCacheNamespace(value: value)
    }
}

public struct NovelInlineImageLoadingContext: Sendable {
    public let loader: any NovelInlineImageDataLoading
    public let cacheNamespace: NovelInlineImageCacheNamespace

    public init(
        loader: any NovelInlineImageDataLoading,
        cacheNamespace: NovelInlineImageCacheNamespace
    ) {
        self.loader = loader
        self.cacheNamespace = cacheNamespace
    }
}

public actor YamiboNovelInlineImageDataLoader: NovelInlineImageDataLoading {
    private let imageDataLoader: any YamiboImageDataLoading
    private let cacheNamespace: YamiboImageCacheNamespace

    public init(client: YamiboClient) {
        imageDataLoader = YamiboImageDataLoader(client: client)
        cacheNamespace = YamiboImageCacheNamespace(value: "novel-inline")
    }

    public init(imageDataLoader: any YamiboImageDataLoading, cacheNamespace: YamiboImageCacheNamespace) {
        self.imageDataLoader = imageDataLoader
        self.cacheNamespace = cacheNamespace
    }

    public func imageData(for imageURL: URL, refererURL: URL) async throws -> Data {
        try await imageDataLoader.imageData(
            for: YamiboImageRequest(
                url: imageURL,
                refererURL: refererURL,
                cacheNamespace: cacheNamespace
            )
        )
    }
}
