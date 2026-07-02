import Foundation

public enum YamiboNetworkConfiguration {
    public static let requestTimeout: TimeInterval = 15
    public static let resourceTimeout: TimeInterval = 15

    public static func makeSession() -> URLSession {
        URLSession(configuration: makeSessionConfiguration())
    }

    public static func makeImageSession() -> URLSession {
        URLSession(configuration: makeImageSessionConfiguration())
    }

    public static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    public static func makeImageSessionConfiguration() -> URLSessionConfiguration {
        let configuration = makeSessionConfiguration()
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    public static func makeRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) -> URLRequest {
        URLRequest(
            url: url,
            cachePolicy: cachePolicy,
            timeoutInterval: requestTimeout
        )
    }
}
