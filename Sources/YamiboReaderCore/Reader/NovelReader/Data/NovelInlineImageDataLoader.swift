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
    private let offlineCacheStore: (any NovelOfflineImageDataProviding)?
    private let threadID: String?

    public init(
        imageDataLoader: any NovelInlineImageDataLoading,
        offlineCacheStore: (any NovelOfflineImageDataProviding)? = nil,
        threadID: String? = nil
    ) {
        self.imageDataLoader = imageDataLoader
        self.offlineCacheStore = offlineCacheStore
        self.threadID = threadID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func imageData(for imageURL: URL, refererURL: URL) async throws -> Data {
        if let offline = await offlineImageData(for: imageURL, refererURL: refererURL) {
            return offline
        }
        return try await imageDataLoader.imageData(for: imageURL, refererURL: refererURL)
    }

    private func offlineImageData(for imageURL: URL, refererURL _: URL) async -> Data? {
        guard let threadID, !threadID.isEmpty else { return nil }
        return await offlineCacheStore?.novelOfflineImageData(for: imageURL, threadID: threadID)
    }
}
