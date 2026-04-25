import Foundation

public struct AccountUIDResolver: Sendable {
    public static let profileURL = URL(string: "https://bbs.yamibo.com/home.php?mod=space&do=profile&mycenter=1&mobile=2")!

    private let sessionStore: SessionStore
    private let session: URLSession

    public init(sessionStore: SessionStore, session: URLSession = .shared) {
        self.sessionStore = sessionStore
        self.session = session
    }

    public func resolveCurrentAccountUID() async throws -> String {
        let sessionState = await sessionStore.load()
        guard sessionState.isLoggedIn, !sessionState.cookie.isEmpty else {
            throw YamiboError.notAuthenticated
        }
        if let uid = normalize(sessionState.accountUID) {
            return uid
        }

        var request = URLRequest(url: Self.profileURL)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(sessionState.cookie, forHTTPHeaderField: "Cookie")
        request.setValue(sessionState.userAgent, forHTTPHeaderField: "User-Agent")

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

        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) ?? ""
        guard let uid = Self.extractAccountUID(finalURL: httpResponse.url, html: html) else {
            throw YamiboError.accountUIDUnavailable
        }
        try await sessionStore.updateAccountUID(uid)
        return uid
    }

    public static func extractAccountUID(finalURL: URL?, html: String) -> String? {
        if let finalURL, let uid = extractAccountUID(from: finalURL.absoluteString) {
            return uid
        }
        return extractAccountUID(from: html)
    }

    private static func extractAccountUID(from text: String) -> String? {
        let patterns = [
            #"uid=(\d+)"#,
            #"space-uid-(\d+)\.html"#,
            #"home\.php\?mod=space&amp;uid=(\d+)"#,
            #"home\.php\?mod=space&uid=(\d+)"#
        ]
        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)),
                let range = Range(match.range(at: 1), in: text)
            else {
                continue
            }
            return String(text[range])
        }
        return nil
    }

    private func normalize(_ uid: String?) -> String? {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
