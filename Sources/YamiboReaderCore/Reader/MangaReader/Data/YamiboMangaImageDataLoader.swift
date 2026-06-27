import Foundation

public actor YamiboMangaImageDataLoader: MangaImageDataLoading {
    private let client: YamiboClient
    private var inFlightTasks: [String: Task<Data, Error>] = [:]

    public init(client: YamiboClient) {
        self.client = client
    }

    public func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        let key = url.absoluteString
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let client = client
        let task = Task<Data, Error> {
            try await Self.fetchImageData(url: url, refererURL: refererURL, client: client)
        }
        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await task.value
    }

    private static func fetchImageData(
        url: URL,
        refererURL: URL?,
        client: YamiboClient
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        if let cookie = client.cookie?.mangaReaderTrimmedNonEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let refererURL {
            request.setValue(refererURL.absoluteString, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await client.session.data(for: request)
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
            return data
        } catch let error as YamiboError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw YamiboError.offline
            default:
                throw YamiboError.underlying(error.localizedDescription)
            }
        }
    }
}
