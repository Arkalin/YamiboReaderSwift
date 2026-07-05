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

    public func imageData(for request: YamiboImageRequest) async throws -> Data {
        try await imageData(for: request, offlineCacheContext: nil)
    }

    public func imageData(
        for request: YamiboImageRequest,
        offlineCacheContext: MangaImageOfflineCacheContext?
    ) async throws -> Data {
        if let offline = await offlineImageData(for: request, context: offlineCacheContext) {
            return offline
        }

        return try await imageDataLoader.imageData(for: request)
    }

    private func offlineImageData(for request: YamiboImageRequest, context: MangaImageOfflineCacheContext?) async -> Data? {
        guard let context, let offlineCacheStore else { return nil }
        guard let membership = await offlineCacheStore.mangaOfflineCacheMembership(
            ownerName: context.ownerName,
            tid: context.tid
        ) else {
            return nil
        }
        guard membership.imageURLs.contains(where: { $0.absoluteString == request.url.absoluteString }) else {
            return nil
        }
        return await offlineCacheStore.offlineImageData(for: request.url)
    }
}
