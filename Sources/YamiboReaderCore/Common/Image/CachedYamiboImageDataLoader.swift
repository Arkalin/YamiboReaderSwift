import Foundation

public actor CachedYamiboImageDataLoader: YamiboImageDataLoading {
    private let cache: any YamiboImageDataCaching
    private let upstream: any YamiboImageDataLoading
    private let retentionPolicy: YamiboImageDataCacheRetentionPolicy
    private var inFlightTasks: [String: Task<Data, Error>] = [:]

    public init(
        cache: any YamiboImageDataCaching,
        upstream: any YamiboImageDataLoading,
        retentionPolicy: YamiboImageDataCacheRetentionPolicy = .evictable
    ) {
        self.cache = cache
        self.upstream = upstream
        self.retentionPolicy = retentionPolicy
    }

    public func imageData(for request: YamiboImageRequest) async throws -> Data {
        if let cached = await cache.data(for: request) {
            return cached
        }

        let key = request.persistentCacheKey
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let cache = cache
        let upstream = upstream
        let retentionPolicy = retentionPolicy
        let task = Task<Data, Error> {
            if let cached = await cache.data(for: request) {
                return cached
            }

            let data = try await upstream.imageData(for: request)
            if !data.isEmpty {
                try? await cache.save(data, for: request, retentionPolicy: retentionPolicy)
            }
            return data
        }

        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await task.value
    }
}
