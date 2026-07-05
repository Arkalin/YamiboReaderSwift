import Foundation

public actor YamiboMangaImageDataLoader: MangaImageDataLoading {
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
