import CryptoKit
import Foundation

public protocol NovelInlineImageDataLoading: Sendable {
    func imageData(for imageURL: URL, refererURL: URL) async throws -> Data
}

public struct NovelInlineImageCacheNamespace: Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func namespace(cookie: String, userAgent: String) -> NovelInlineImageCacheNamespace {
        let rawValue = "\(userAgent)\u{1F}\(cookie)"
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return NovelInlineImageCacheNamespace(
            value: digest.map { String(format: "%02x", $0) }.joined()
        )
    }
}

public struct NovelInlineImageLoadingContext: Sendable {
    public let loader: any NovelInlineImageDataLoading
    public let cacheNamespace: NovelInlineImageCacheNamespace

    public init(
        loader: any NovelInlineImageDataLoading,
        cacheNamespace: NovelInlineImageCacheNamespace
    ) {
        self.loader = loader
        self.cacheNamespace = cacheNamespace
    }
}

public actor YamiboNovelInlineImageDataLoader: NovelInlineImageDataLoading {
    private let client: YamiboClient
    private var inFlightTasks: [RequestKey: Task<Data, Error>] = [:]

    public init(client: YamiboClient) {
        self.client = client
    }

    public func imageData(for imageURL: URL, refererURL: URL) async throws -> Data {
        let key = RequestKey(imageURL: imageURL, refererURL: refererURL)
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let client = client
        let task = Task<Data, Error> {
            try await Self.fetchImageData(
                imageURL: imageURL,
                refererURL: refererURL,
                client: client
            )
        }
        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await task.value
    }

    private struct RequestKey: Hashable {
        let imageURL: URL
        let refererURL: URL
    }

    private static func fetchImageData(
        imageURL: URL,
        refererURL: URL,
        client: YamiboClient
    ) async throws -> Data {
        var request = YamiboNetworkConfiguration.makeRequest(url: imageURL)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        if let cookie = client.cookie?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.setValue(refererURL.absoluteString, forHTTPHeaderField: "Referer")

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
        } catch {
            throw YamiboError.underlying(error.localizedDescription)
        }
    }
}
