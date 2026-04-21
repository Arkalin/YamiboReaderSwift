import Foundation

public struct YamiboClient: Sendable {
    public var session: URLSession
    public var cookie: String?
    public var userAgent: String

    public init(
        session: URLSession = .shared,
        cookie: String? = nil,
        userAgent: String = YamiboDefaults.defaultMobileUserAgent
    ) {
        self.session = session
        self.cookie = cookie
        self.userAgent = userAgent
    }

    public func fetchHTML(for route: YamiboRoute, userAgent: String? = nil) async throws -> String {
        try await fetchHTML(url: route.url, userAgent: userAgent)
    }

    public func fetchHTML(url: URL, userAgent: String? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.setValue(userAgent ?? self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YamiboError.invalidResponse(statusCode: nil)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw YamiboError.notAuthenticated
            }
            throw YamiboError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw YamiboError.unreadableBody
        }
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw YamiboError.emptyHTML
        }
        return html
    }
}
