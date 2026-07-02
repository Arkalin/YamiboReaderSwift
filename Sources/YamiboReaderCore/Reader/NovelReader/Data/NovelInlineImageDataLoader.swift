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
