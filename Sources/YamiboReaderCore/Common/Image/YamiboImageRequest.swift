import CryptoKit
import Foundation

public struct YamiboImageCacheNamespace: Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func namespace(cookie: String, userAgent: String) -> YamiboImageCacheNamespace {
        let rawValue = "\(userAgent)\u{1F}\(cookie)"
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return YamiboImageCacheNamespace(
            value: digest.map { String(format: "%02x", $0) }.joined()
        )
    }
}

public struct YamiboImageRequest: Hashable, Sendable {
    public var url: URL
    public var refererURL: URL?
    public var cacheNamespace: YamiboImageCacheNamespace

    public init(
        url: URL,
        refererURL: URL? = nil,
        cacheNamespace: YamiboImageCacheNamespace
    ) {
        self.url = url
        self.refererURL = refererURL
        self.cacheNamespace = cacheNamespace
    }

    public var cacheKey: String {
        [
            url.absoluteString,
            refererURL?.absoluteString ?? "",
            cacheNamespace.value
        ].joined(separator: "\u{1F}")
    }
}

public protocol YamiboImageDataLoading: Sendable {
    func imageData(for request: YamiboImageRequest) async throws -> Data
}

public struct YamiboImageLoadingContext: Sendable {
    public let dataLoader: any YamiboImageDataLoading
    public let cacheNamespace: YamiboImageCacheNamespace

    public init(
        dataLoader: any YamiboImageDataLoading,
        cacheNamespace: YamiboImageCacheNamespace
    ) {
        self.dataLoader = dataLoader
        self.cacheNamespace = cacheNamespace
    }
}

public actor YamiboImageDataLoader: YamiboImageDataLoading {
    private let client: YamiboClient
    private var inFlightTasks: [YamiboImageRequest: Task<Data, Error>] = [:]

    public init(client: YamiboClient) {
        self.client = client
    }

    public func imageData(for request: YamiboImageRequest) async throws -> Data {
        if let task = inFlightTasks[request] {
            return try await task.value
        }

        let client = client
        let task = Task<Data, Error> {
            try await Self.fetchImageData(request: request, client: client)
        }
        inFlightTasks[request] = task
        defer { inFlightTasks.removeValue(forKey: request) }
        return try await task.value
    }

    private static func fetchImageData(
        request imageRequest: YamiboImageRequest,
        client: YamiboClient
    ) async throws -> Data {
        var request = YamiboNetworkConfiguration.makeRequest(url: imageRequest.url)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        if let cookie = client.cookie?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let refererURL = imageRequest.refererURL {
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
        } catch {
            throw YamiboError.underlying(error.localizedDescription)
        }
    }
}
