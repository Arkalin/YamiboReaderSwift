import Foundation

public actor CachedMangaImageDataLoader: MangaImageDataLoading {
    private let imageDataLoader: any YamiboImageDataLoading
    private let offlineCacheStore: (any MangaOfflineCacheStoring)?

    public init(
        imageDataLoader: any YamiboImageDataLoading,
        offlineCacheStore: (any MangaOfflineCacheStoring)? = nil
    ) {
        self.imageDataLoader = imageDataLoader
        self.offlineCacheStore = offlineCacheStore
    }

    public func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        try await imageData(for: url, refererURL: refererURL, offlineCacheContext: nil)
    }

    public func imageData(
        for url: URL,
        refererURL: URL?,
        offlineCacheContext: MangaImageOfflineCacheContext?
    ) async throws -> Data {
        if let offline = await offlineImageData(for: url, context: offlineCacheContext) {
            return offline
        }

        return try await imageDataLoader.imageData(
            for: YamiboImageRequest(
                url: url,
                refererURL: refererURL
            )
        )
    }

    private func offlineImageData(for url: URL, context: MangaImageOfflineCacheContext?) async -> Data? {
        guard let context, let offlineCacheStore else { return nil }
        guard let membership = await offlineCacheStore.membership(
            ownerName: context.ownerName,
            tid: context.tid
        ) else {
            return nil
        }
        guard membership.imageURLs.contains(where: { $0.absoluteString == url.absoluteString }) else {
            return nil
        }
        return await offlineCacheStore.offlineImageData(for: url)
    }
}
