import Foundation

public actor YamiboMangaImageDataLoader: MangaImageDataLoading {
    private let imageDataLoader: any YamiboImageDataLoading
    private let cacheNamespace: YamiboImageCacheNamespace

    public init(client: YamiboClient) {
        imageDataLoader = YamiboImageDataLoader(client: client)
        cacheNamespace = YamiboImageCacheNamespace(value: "manga")
    }

    public init(imageDataLoader: any YamiboImageDataLoading, cacheNamespace: YamiboImageCacheNamespace) {
        self.imageDataLoader = imageDataLoader
        self.cacheNamespace = cacheNamespace
    }

    public func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        try await imageDataLoader.imageData(
            for: YamiboImageRequest(
                url: url,
                refererURL: refererURL,
                cacheNamespace: cacheNamespace
            )
        )
    }
}
