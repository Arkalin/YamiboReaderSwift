import Foundation

public struct SessionState: Codable, Hashable, Sendable {
    public var cookie: String
    public var userAgent: String
    public var isLoggedIn: Bool
    public var lastUpdatedAt: Date?
    public var accountUID: String?

    public init(
        cookie: String = "",
        userAgent: String = YamiboDefaults.defaultMobileUserAgent,
        isLoggedIn: Bool = false,
        lastUpdatedAt: Date? = nil,
        accountUID: String? = nil
    ) {
        self.cookie = cookie
        self.userAgent = userAgent
        self.isLoggedIn = isLoggedIn
        self.lastUpdatedAt = lastUpdatedAt
        self.accountUID = accountUID
    }

    public static func hasAuthenticationCookie(_ cookieHeader: String) -> Bool {
        cookieHeader
            .split(separator: ";")
            .contains { part in
                part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix("EeqY_2132_auth=")
            }
    }
}
