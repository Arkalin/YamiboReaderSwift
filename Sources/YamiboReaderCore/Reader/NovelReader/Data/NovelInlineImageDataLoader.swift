import Foundation

public struct NovelInlineImageLoadingContext: Sendable {
    public let loader: any YamiboImageDataLoading

    public init(loader: any YamiboImageDataLoading) {
        self.loader = loader
    }
}

public actor YamiboNovelInlineImageDataLoader: YamiboImageDataLoading {
    private let imageDataLoader: any YamiboImageDataLoading

    public init(client: YamiboClient) {
        imageDataLoader = YamiboImageDataLoader(client: client)
    }

    public init(imageDataLoader: any YamiboImageDataLoading) {
        self.imageDataLoader = imageDataLoader
    }

    public func imageData(for request: YamiboImageRequest) async throws -> Data {
        try await imageDataLoader.imageData(for: request)
    }
}

public actor CachedNovelInlineImageDataLoader: YamiboImageDataLoading {
    private let imageDataLoader: any YamiboImageDataLoading
    private let offlineCacheStore: (any NovelOfflineImageDataProviding)?
    private let threadID: String?

    public init(
        imageDataLoader: any YamiboImageDataLoading,
        offlineCacheStore: (any NovelOfflineImageDataProviding)? = nil,
        threadID: String? = nil
    ) {
        self.imageDataLoader = imageDataLoader
        self.offlineCacheStore = offlineCacheStore
        self.threadID = threadID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func imageData(for request: YamiboImageRequest) async throws -> Data {
        if let offline = await offlineImageData(for: request) {
            return offline
        }
        return try await imageDataLoader.imageData(for: request)
    }

    private func offlineImageData(for request: YamiboImageRequest) async -> Data? {
        guard let threadID, !threadID.isEmpty else { return nil }
        return await offlineCacheStore?.novelOfflineImageData(for: request.url, threadID: threadID)
    }
}
