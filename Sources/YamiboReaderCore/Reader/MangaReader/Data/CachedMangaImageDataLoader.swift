import Foundation

public actor CachedMangaImageDataLoader: MangaImageDataLoading {
    private let cache: any MangaImageDataCaching
    private let upstream: any MangaImageDataLoading
    private var inFlightTasks: [String: Task<Data, Error>] = [:]

    public init(
        cache: any MangaImageDataCaching,
        upstream: any MangaImageDataLoading
    ) {
        self.cache = cache
        self.upstream = upstream
    }

    public func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        if let cached = await cache.data(for: url) {
            return cached
        }

        let key = url.absoluteString
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let cache = cache
        let upstream = upstream
        let task = Task<Data, Error> {
            if let cached = await cache.data(for: url) {
                return cached
            }

            let data = try await upstream.imageData(for: url, refererURL: refererURL)
            try? await cache.save(data, for: url)
            return data
        }

        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await task.value
    }
}
