import Foundation

public protocol NovelInlineImageDataLoading: Sendable {
    func imageData(for imageURL: URL, refererURL: URL) async throws -> Data
}

public struct NovelInlineImageLoadingContext: Sendable {
    public let loader: any NovelInlineImageDataLoading

    public init(loader: any NovelInlineImageDataLoading) {
        self.loader = loader
    }
}

public actor YamiboNovelInlineImageDataLoader: NovelInlineImageDataLoading {
    private let imageDataLoader: any YamiboImageDataLoading

    public init(client: YamiboClient) {
        imageDataLoader = YamiboImageDataLoader(client: client)
    }

    public init(imageDataLoader: any YamiboImageDataLoading) {
        self.imageDataLoader = imageDataLoader
    }

    public func imageData(for imageURL: URL, refererURL: URL) async throws -> Data {
        try await imageDataLoader.imageData(
            for: YamiboImageRequest(
                url: imageURL,
                refererURL: refererURL
            )
        )
    }
}

public actor CachedNovelInlineImageDataLoader: NovelInlineImageDataLoading {
    private let imageDataLoader: any NovelInlineImageDataLoading
    private let offlineCacheStore: (any OfflineCacheStoring)?

    public init(
        imageDataLoader: any NovelInlineImageDataLoading,
        offlineCacheStore: (any OfflineCacheStoring)? = nil
    ) {
        self.imageDataLoader = imageDataLoader
        self.offlineCacheStore = offlineCacheStore
    }

    public func imageData(for imageURL: URL, refererURL: URL) async throws -> Data {
        if let offline = await offlineImageData(for: imageURL, refererURL: refererURL) {
            return offline
        }
        return try await imageDataLoader.imageData(for: imageURL, refererURL: refererURL)
    }

    private func offlineImageData(for imageURL: URL, refererURL: URL) async -> Data? {
        guard let offlineCacheStore else { return nil }
        let canonicalRefererURL = ReaderCacheIdentity.canonicalThreadURL(from: refererURL)
        let entries = await offlineCacheStore.allNovelOfflineCacheEntries()
        guard entries.contains(where: { entry in
            ReaderCacheIdentity.canonicalThreadURL(from: entry.document.threadURL) == canonicalRefererURL &&
                entry.imageURLs.contains { $0.absoluteString == imageURL.absoluteString }
        }) else {
            return nil
        }
        return await offlineCacheStore.offlineImageData(for: imageURL)
    }
}
