import Foundation

public actor CachedMangaImageDataLoader: MangaImageDataLoading {
    private let cache: any MangaImageDataCaching
    private let upstream: any MangaImageDataLoading
    private let offlineCacheStore: (any MangaOfflineCacheStoring)?
    private var inFlightTasks: [String: Task<Data, Error>] = [:]

    public init(
        cache: any MangaImageDataCaching,
        upstream: any MangaImageDataLoading,
        offlineCacheStore: (any MangaOfflineCacheStoring)? = nil
    ) {
        self.cache = cache
        self.upstream = upstream
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
