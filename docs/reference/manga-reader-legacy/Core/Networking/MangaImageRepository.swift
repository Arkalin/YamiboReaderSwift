import Foundation

public struct MangaImageRequest: Hashable, Sendable {
    public var imageURL: URL
    public var refererURL: URL

    public init(imageURL: URL, refererURL: URL) {
        self.imageURL = imageURL
        self.refererURL = refererURL
    }
}

public actor MangaImageRepository {
    private let session: URLSession
    private let sessionStore: SessionStore
    private let cacheStore: MangaImageCacheStore
    private var inFlightTasks: [String: Task<Data, Error>] = [:]

    public init(
        session: URLSession = .shared,
        sessionStore: SessionStore = SessionStore(),
        cacheStore: MangaImageCacheStore = MangaImageCacheStore()
    ) {
        self.session = session
        self.sessionStore = sessionStore
        self.cacheStore = cacheStore
    }

    public func imageData(for request: MangaImageRequest) async throws -> Data {
        if let cached = await cacheStore.loadData(for: request.imageURL) {
            return cached
        }

        let key = request.imageURL.absoluteString
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            let sessionState = await self.sessionStore.load()
            var urlRequest = URLRequest(url: request.imageURL)
            urlRequest.setValue(sessionState.userAgent, forHTTPHeaderField: "User-Agent")
            if !sessionState.cookie.isEmpty {
                urlRequest.setValue(sessionState.cookie, forHTTPHeaderField: "Cookie")
            }
            urlRequest.setValue(request.refererURL.absoluteString, forHTTPHeaderField: "Referer")

            let (data, response) = try await self.session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw YamiboError.invalidResponse(statusCode: nil)
            }
            guard 200 ..< 300 ~= httpResponse.statusCode else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw YamiboError.notAuthenticated
                }
                throw YamiboError.invalidResponse(statusCode: httpResponse.statusCode)
            }
            guard !data.isEmpty else {
                throw YamiboError.unreadableBody
            }

            try await self.cacheStore.save(data, for: request.imageURL)
            return data
        }

        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await task.value
    }

    public func prefetch(_ requests: [MangaImageRequest]) async {
        let uniqueRequests = Array(
            Dictionary(uniqueKeysWithValues: requests.map { ($0.imageURL.absoluteString, $0) }).values
        )

        await withTaskGroup(of: Void.self) { group in
            for request in uniqueRequests {
                group.addTask {
                    _ = try? await self.imageData(for: request)
                }
            }
        }
    }
}
