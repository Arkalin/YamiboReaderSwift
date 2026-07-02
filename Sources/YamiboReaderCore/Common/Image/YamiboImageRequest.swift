import Foundation

public struct YamiboImageRequest: Hashable, Sendable {
    public var url: URL
    public var refererURL: URL?

    public init(
        url: URL,
        refererURL: URL? = nil
    ) {
        self.url = url
        self.refererURL = refererURL
    }

    public var cacheKey: String {
        url.absoluteString
    }
}

public protocol YamiboImageDataLoading: Sendable {
    func imageData(for request: YamiboImageRequest) async throws -> Data
}

public struct YamiboImageLoadingContext: Sendable {
    public let dataLoader: any YamiboImageDataLoading

    public init(dataLoader: any YamiboImageDataLoading) {
        self.dataLoader = dataLoader
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
